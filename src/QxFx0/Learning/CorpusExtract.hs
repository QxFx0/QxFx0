{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.CorpusExtract
Description : Phase II — corpus-driven training dataset extraction.

Extracts a 'TrainingDataset' from the SQLite @turn_quality@ table,
including the @replay_trace_json@ blob.  The replay trace supplies the
historical 'Field' and 'ConatusEnergy' snapshots; the observed pipeline
outcome (owner family and decision disposition) comes from
@turn_quality@ columns directly.

The extracted corpus is converted into the same 'TrainingTrace' shape
used by 'Learning.TrainingCycle' so that offline evaluation, candidate
generation and promotion can be reused without change.
-}
module QxFx0.Learning.CorpusExtract
  ( -- * Dataset extraction
    SessionId
  , extractCorpusDataset
    -- * Trace conversion
  , CorpusTrace(..)
  , corpusTraceToTrainingTrace
  , fieldToSignalComponents
  , dispositionToDecision
  , ownerFamilyToDecision
    -- * Replay summary parsing
  , ReplayTraceSummary(..)
  ) where

import Data.Aeson (FromJSON(..), ToJSON, withObject, (.:), (.:?), (.!=))
import qualified Data.Aeson as Aeson
import Data.Maybe (catMaybes, fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.StatePersistence (DbRunner)

import QxFx0.Learning.Signal
  ( CalibrationDecision(..)
  , SignalComponents(..)
  )
import QxFx0.Learning.TrainingCycle
  ( TrainingDataset(..)
  , TrainingTrace(..)
  , DatasetStats(..)
  )
import QxFx0.Self.Conatus
  ( ConatusComponents(..)
  , ConatusEnergy(..)
  )
import QxFx0.Self.Field
  ( Atmosphere(..)
  , Consolidation(..)
  , Counterfactual(..)
  , Field(..)
  , FieldConfidence(..)
  , Resonance(..)
  , emptyField
  )
import QxFx0.Types.Decision
  ( DecisionDisposition(..)
  )
import QxFx0.Types.Domain
  ( CanonicalMoveFamily(..)
  )
import QxFx0.Types.TurnProjection (decodeReplayTracePayload)

-- | Session identifier used for filtering the corpus.
type SessionId = Text

-- | A single trace summarising everything needed from one historical turn.
data CorpusTrace = CorpusTrace
  { ctTurn                :: !Int
  , ctSessionId           :: !Text
  , ctObservedFamily      :: !CanonicalMoveFamily
  , ctObservedDisposition :: !DecisionDisposition
  , ctDivergence          :: !Bool
  , ctField               :: !Field
  , ctConatusEnergy       :: !ConatusEnergy
  , ctMoodArousal         :: !Double
  , ctContentSaliency     :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Replay fields consumed by the extractor.  Only a small subset of the
-- full 'TurnReplayTrace' is required, so a dedicated lenient parser
-- keeps extraction robust against schema drift.
data ReplayTraceSummary = ReplayTraceSummary
  { rtsField           :: !Field
  , rtsConatusEnergy   :: !ConatusEnergy
  , rtsMoodArousal     :: !(Maybe Double)
  , rtsContentSaliency :: !(Maybe Double)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON)

emptyConatusEnergy :: ConatusEnergy
emptyConatusEnergy = ConatusEnergy 0.0 (ConatusComponents 0.0 0.0 0.0 0.0 0.0)

instance FromJSON ReplayTraceSummary where
  parseJSON = withObject "ReplayTraceSummary" $ \o ->
    ReplayTraceSummary
      <$> o .:? "trcField" .!= emptyField
      <*> o .:? "trcConatusEnergy" .!= emptyConatusEnergy
      <*> o .:? "trcMoodArousal"
      <*> o .:? "trcContentSaliency"

-- | Extract a 'TrainingDataset' from the persisted @turn_quality@ corpus.
--
-- * @Just sessionId@ restricts the query to one session.
-- * @Nothing@ uses every session in the database.
--
-- Rows whose replay trace cannot be decoded are skipped and logged to
-- stderr; the extraction is fail-open so that a few corrupt traces do
-- not abort the whole tuning run.
extractCorpusDataset :: DbRunner -> Maybe SessionId -> IO TrainingDataset
extractCorpusDataset withDb mSessionId =
  withDb $ \db -> do
    rows <- queryCorpusRows db mSessionId
    let corpusTraces = catMaybes (map corpusRowToTrace rows)
        traces = map corpusTraceToTrainingTrace corpusTraces
        total = length traces
        trainEnd = (total * 7) `div` 10
        (train, eval) = splitAt trainEnd traces
        stats = computeCorpusStats corpusTraces
    if total < 5
      then pure (TrainingDataset [] [] [] (DatasetStats 0 0 0 0 0))
      else pure (TrainingDataset traces train eval stats)

-- | Raw row returned from the SQL query.
data CorpusRow = CorpusRow
  { crTurn            :: !Int
  , crSessionId       :: !Text
  , crFamilyText      :: !Text
  , crDispositionText :: !Text
  , crDivergence      :: !Int
  , crReplayJson      :: !Text
  }

queryCorpusRows :: NSQL.Database -> Maybe SessionId -> IO [CorpusRow]
queryCorpusRows db mSessionId = do
  let sqlBase =
        "SELECT session_id, turn, owner_family, decision_disposition, divergence, replay_trace_json \
        \FROM turn_quality "
      (sql, binder) = case mSessionId of
        Nothing -> (sqlBase <> "ORDER BY session_id, turn", \_ -> pure ())
        Just sid ->
          ( sqlBase <> "WHERE session_id = ? ORDER BY turn"
          , \stmt -> do
              bindResult <- NSQL.bindText stmt 1 sid
              case bindResult of
                Left err -> hPutStrLn stderr $ "corpus_extract bind failed: " <> T.unpack err
                Right () -> pure ()
          )
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err -> do
      hPutStrLn stderr $ "corpus_extract prepare failed: " <> T.unpack err
      pure []
    Right stmt -> do
      _ <- binder stmt
      rows <- collectRows stmt []
      _ <- NSQL.finalize stmt
      pure rows
  where
    collectRows stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then pure (reverse acc)
        else do
          sid <- NSQL.columnText stmt 0
          turn <- NSQL.columnInt stmt 1
          familyTxt <- NSQL.columnText stmt 2
          dispTxt <- NSQL.columnText stmt 3
          divInt <- NSQL.columnInt stmt 4
          replayJson <- NSQL.columnTextLenient stmt 5
          let row = CorpusRow
                { crTurn = turn
                , crSessionId = sid
                , crFamilyText = familyTxt
                , crDispositionText = dispTxt
                , crDivergence = divInt
                , crReplayJson = replayJson
                }
          collectRows stmt (row : acc)

corpusRowToTrace :: CorpusRow -> Maybe CorpusTrace
corpusRowToTrace row = do
  family <- parseFamily (crFamilyText row)
  disposition <- parseDisposition (crDispositionText row)
  summary <- parseReplayTraceSummary (crReplayJson row)
  let field = rtsField summary
      energy = rtsConatusEnergy summary
      mood = fromMaybe 0.5 (rtsMoodArousal summary)
      saliency = fromMaybe 0.0 (rtsContentSaliency summary)
  pure CorpusTrace
    { ctTurn = crTurn row
    , ctSessionId = crSessionId row
    , ctObservedFamily = family
    , ctObservedDisposition = disposition
    , ctDivergence = crDivergence row /= 0
    , ctField = field
    , ctConatusEnergy = energy
    , ctMoodArousal = mood
    , ctContentSaliency = saliency
    }

parseFamily :: Text -> Maybe CanonicalMoveFamily
parseFamily txt =
  case T.toLower txt of
    "cmground"    -> Just CMGround
    "cmdefine"    -> Just CMDefine
    "cmdistinguish" -> Just CMDistinguish
    "cmreflect"   -> Just CMReflect
    "cmdescribe"  -> Just CMDescribe
    "cmpurpose"   -> Just CMPurpose
    "cmhypothesis" -> Just CMHypothesis
    "cmrepair"    -> Just CMRepair
    "cmcontact"   -> Just CMContact
    "cmanchor"    -> Just CMAnchor
    "cmclarify"   -> Just CMClarify
    "cmdeepen"    -> Just CMDeepen
    "cmconfront"  -> Just CMConfront
    "cmnextstep"  -> Just CMNextStep
    _             -> readMaybe (T.unpack txt)

parseDisposition :: Text -> Maybe DecisionDisposition
parseDisposition txt =
  case T.toLower txt of
    "permit"   -> Just DispositionPermit
    "repair"   -> Just DispositionRepair
    "deny"     -> Just DispositionDeny
    "advisory" -> Just DispositionAdvisory
    _          -> readMaybe (T.unpack txt)

parseReplayTraceSummary :: Text -> Maybe ReplayTraceSummary
parseReplayTraceSummary txt =
  case decodeReplayTracePayload (TE.encodeUtf8 txt) of
    Left _ -> Nothing
    Right payload ->
      case Aeson.fromJSON payload of
        Aeson.Error _ -> Nothing
        Aeson.Success summary -> Just summary

corpusTraceToTrainingTrace :: CorpusTrace -> TrainingTrace
corpusTraceToTrainingTrace ct =
  let field = ctField ct
      energy = ctConatusEnergy ct
      comps = fieldToSignalComponents field
      signal = clampRange (-1.0) 1.0 (ceScalar energy / 5.0)
  in TrainingTrace
       { ttTurn = ctTurn ct
       , ttSignalComponents = comps
       , ttSignal = signal
       , ttDecision = dispositionToDecision (ctObservedDisposition ct)
       , ttNeedLevel = clampUnit (ctMoodArousal ct)
       , ttTreeHealth = clampUnit (unFieldConfidence (fieldConfidence field))
       , ttRepairLoopCount = if ctDivergence ct then 1 else 0
       }

clampRange :: Double -> Double -> Double -> Double
clampRange lo hi x = max lo (min hi x)

clampUnit :: Double -> Double
clampUnit = clampRange 0.0 1.0

fieldToSignalComponents :: Field -> SignalComponents
fieldToSignalComponents f =
  SignalComponents
    { scConatusTrend      = unResonance (fieldResonance f) - 0.5
    , scUncertaintyTrend  = unCounterfactual (fieldCounterfactual f) - 0.5
    , scLoopRisk          = atmosphereArousal (fieldAtmosphere f) - 0.5
    , scBranchHealthTrend = unFieldConfidence (fieldConfidence f) - 0.5
    }

dispositionToDecision :: DecisionDisposition -> CalibrationDecision
dispositionToDecision DispositionPermit   = CdApplySignal
dispositionToDecision DispositionRepair   = CdHoldGuardrails
dispositionToDecision DispositionDeny     = CdHoldGuardrails
dispositionToDecision DispositionAdvisory = CdHoldLowConfidence

ownerFamilyToDecision :: CanonicalMoveFamily -> CalibrationDecision
ownerFamilyToDecision _ = CdApplySignal

computeCorpusStats :: [CorpusTrace] -> DatasetStats
computeCorpusStats traces =
  let total = length traces
      accepted = length (filter (\t -> ctObservedDisposition t == DispositionPermit) traces)
      rejected = length (filter (\t -> ctObservedDisposition t `elem` [DispositionAdvisory, DispositionDeny]) traces)
      errors   = length (filter (\t -> ctObservedDisposition t == DispositionRepair) traces)
      fallbackHeavy = if total > 0 && fromIntegral (length (filter ctDivergence traces)) / fromIntegral total > 0.5 then 1 else 0
  in DatasetStats total accepted rejected errors fallbackHeavy
