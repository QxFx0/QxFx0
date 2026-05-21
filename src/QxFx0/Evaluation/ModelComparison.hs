{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Evaluation.ModelComparison
Description : Fireworks multi-model A/B evaluation harness.

Deterministic corpus, session runner, metrics aggregation, and
incident detection for comparing external LLM transports.

Constraints:
- Identical corpus and policy across all models.
- Per-model state fork so sessions are independent.
- Incident detection is fail-closed: any anomaly is reported,
  never silently swallowed.
- Mock-based tests use model-characteristic mock tables for
  deterministic 360-turn simulation.
-}
module QxFx0.Evaluation.ModelComparison
  ( -- * Types
    ModelId
  , TurnPrompt(..)
  , TurnResult(..)
  , SessionOutcome(..)
  , ModelOutcome(..)
  , ComparisonRun(..)
  , ComparisonIncident(..)
  , SessionMode(..)
    -- * Corpus and runner
  , deterministicCorpus
  , runTurn
  , runModelSession
  , runInterleavedSession
  , runComparison
    -- * Aggregation and incident detection
  , aggregateSession
  , aggregateModel
  , detectIncidents
  , renderComparisonRun
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (sortBy)
import qualified Data.Map.Strict as M
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import GHC.Generics (Generic)
import System.Random (mkStdGen, randoms)

import QxFx0.Bridge.ExternalLLM
  ( LLMTransport(..)
  , queryExternalTool
  )
import QxFx0.Learning.Loop
  ( LearningTelemetry(..)
  , runLearningStep
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Tool
  ( ExternalTool(..)
  , ToolDomain(..)
  )
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  )
import QxFx0.Types.State.Dialogue (DialogueState(..))
import QxFx0.Types.State.System (SystemState(..), emptySystemState, ssTurnCount)
import Control.Monad (foldM)

-- ---------------------------------------------------------------------------
-- Types

-- | Canonical model identifier (e.g. "glm-5p1").
type ModelId = Text

-- | One entry in the deterministic evaluation corpus.
data TurnPrompt = TurnPrompt
  { tpIndex :: !Int
  , tpText  :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Result of one evaluation turn.
data TurnResult = TurnResult
  { trModelId     :: !ModelId
  , trPromptIndex :: !Int
  , trOutcome     :: !(Either ExternalQueryError ExternalQueryResponse)
  , trLatencyMs   :: !Int
  , trTelemetry   :: !LearningTelemetry
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Aggregated metrics for a single model session.
data SessionOutcome = SessionOutcome
  { soModelId               :: !ModelId
  , soSessionId             :: !Int
  , soTotalTurns            :: !Int
  , soSuccessCount          :: !Int
  , soTransportErrorCount   :: !Int
  , soParseRejectCount      :: !Int
  , soValidationRejectCount :: !Int
  , soSandboxRejectCount    :: !Int
  , soSandboxAcceptCount    :: !Int
  , soTotalLatencyMs        :: !Int
  , soIncidents             :: ![ComparisonIncident]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Incident detected during session analysis.
data ComparisonIncident
  = IncidentConsecutiveTransportErrors !ModelId !Int !Int
    -- ^ model, startTurn(1-based), count
  | IncidentConsecutiveValidatorRejects !ModelId !Int !Int
    -- ^ model, startTurn(1-based), count
  | IncidentConsecutiveSandboxRejects !ModelId !Int !Text !Int
    -- ^ model, startTurn(1-based), degradationTag, count
  | IncidentRequestRejectLoop !ModelId !Int
    -- ^ model, loopLength
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Per-model outcome across all sessions.
data ModelOutcome = ModelOutcome
  { moModelId              :: !ModelId
  , moSessions             :: ![SessionOutcome]
  , moAvgSuccessRate       :: !Double
  , moAvgLatencyMs         :: !Double
  , moAvgValidatorAcceptRate :: !Double
  , moAvgSandboxPassRate     :: !Double
  , moTotalIncidents       :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Full comparison run.
data ComparisonRun = ComparisonRun
  { crRunId         :: !Text
  , crTimestamp     :: !UTCTime
  , crModelOutcomes :: ![ModelOutcome]
  , crGlobalIncidents :: ![ComparisonIncident]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Execution mode for a session.
data SessionMode = Sequential | Interleaved
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- ---------------------------------------------------------------------------
-- Corpus

-- | Deterministic 40-prompt corpus.  Identical for every model.
-- Prompts cover Russian philosophical vocabulary and morphology
-- queries so the parser, validator, and sandbox are exercised.
deterministicCorpus :: [TurnPrompt]
deterministicCorpus = zipWith TurnPrompt [1..]
  [ "что такое свобода"
  , "тема диалектики"
  , "как склоняется слово 'книга'"
  , "Explore the nature of consciousness"
  , "fail test transport error"
  , "определение справедливости"
  , "тема бытия и ничто"
  , "как склоняется слово 'свобода'"
  , "What is the meaning of existence"
  , "fail second error case"
  , "определение истины"
  , "тема времени"
  , "как склоняется слово 'истина'"
  , "Explain phenomenological reduction"
  , "fail third error cluster"
  , "определение добра"
  , "тема воли"
  , "как склоняется слово 'воля'"
  , "Describe transcendental idealism"
  , "fail fourth error"
  , "определение красоты"
  , "тема смерти"
  , "как склоняется слово 'смерть'"
  , "Analyze categorical imperative"
  , "fail fifth error"
  , "определение долга"
  , "тема ответственности"
  , "как склоняется слово 'долг'"
  , "Discuss ethical egoism"
  , "fail sixth error"
  , "определение власти"
  , "тема государства"
  , "как склоняется слово 'власть'"
  , "Evaluate social contract theory"
  , "fail seventh error"
  , "определение права"
  , "тема закона"
  , "как склоняется слово 'право'"
  , "Interpret hermeneutic circle"
  , "fail eighth error"
  ]

-- ---------------------------------------------------------------------------
-- Runner

-- | Single turn: query external tool, run learning loop, capture telemetry.
runTurn
  :: SystemState
  -> LLMTransport
  -> ExternalTool
  -> LearningNeed
  -> ModelId
  -> TurnPrompt
  -> IO (SystemState, TurnResult)
runTurn ss transport tool need modelId prompt = do
  t0 <- getCurrentTime
  result <- queryExternalTool transport tool need (tpText prompt)
  t1 <- getCurrentTime
  let latency = round (diffUTCTime t1 t0 * 1000.0) :: Int
      (ss', tel) = runLearningStep ss tool need (tpText prompt) (Just result)
      d    = ssDialogue ss
      ss'' = ss' { ssDialogue = d { dsTurnCount = dsTurnCount d + 1 } }
      tr = TurnResult
        { trModelId     = modelId
        , trPromptIndex = tpIndex prompt
        , trOutcome     = result
        , trLatencyMs   = latency
        , trTelemetry   = tel
        }
  return (ss'', tr)

-- | Run one model through all prompts sequentially.
-- State is forked from the supplied baseline.
runModelSession
  :: Int           -- ^ session id
  -> ModelId
  -> LLMTransport
  -> [TurnPrompt]
  -> SystemState   -- ^ baseline state
  -> IO (SystemState, [TurnResult])
runModelSession _sessionId modelId transport prompts ss0 =
  let tool = ExternalTool "llm-augment" DomainLexicon 0.7 True
      need = NeedLexiconExtension
      go ss [] acc = return (ss, reverse acc)
      go ss (p:ps) acc = do
        (ss', tr) <- runTurn ss transport tool need modelId p
        go ss' ps (tr : acc)
  in go ss0 prompts []

-- | Deterministic Fisher-Yates shuffle keyed by an integer seed.
deterministicShuffle :: Int -> [a] -> [a]
deterministicShuffle seed xs =
  let gen = mkStdGen seed
      keys = take (length xs) (randoms gen :: [Int])
  in map snd (sortBy (comparing fst) (zip keys xs))

-- | Run an interleaved session: every prompt is issued to every model,
-- but turn order is deterministically shuffled per session seed.
-- Each model carries its own state fork.
runInterleavedSession
  :: Int
  -> [(ModelId, LLMTransport)]
  -> [TurnPrompt]
  -> SystemState
  -> IO [(ModelId, [TurnResult])]
runInterleavedSession sessionId models prompts ss0 = do
  let modelIds = map fst models
      transports = M.fromList models
      states0 = M.fromList [(mid, ss0) | mid <- modelIds]
      pairs = concatMap (\p -> [(mid, p) | mid <- modelIds]) prompts
      shuffled = deterministicShuffle sessionId pairs
  (states, acc) <- foldM (runPair transports) (states0, M.empty) shuffled
  let results = map (\mid -> (mid, reverse (M.findWithDefault [] mid acc))) modelIds
      -- Restore final states so caller can inspect them if desired
      _finalStates = states
  return results
  where
    tool = ExternalTool "llm-augment" DomainLexicon 0.7 True
    need = NeedLexiconExtension

    runPair trans (states, acc) (mid, prompt) =
      case M.lookup mid trans of
        Nothing -> return (states, acc)
        Just transport ->
          case M.lookup mid states of
            Nothing -> return (states, acc)
            Just ss -> do
              (ss', tr) <- runTurn ss transport tool need mid prompt
              let states' = M.insert mid ss' states
                  acc'    = M.insertWith (++) mid [tr] acc
              return (states', acc')

-- | Full comparison run across all models and sessions.
-- Each session starts from the same baseline state.
runComparison
  :: Text                       -- ^ run identifier
  -> SessionMode
  -> [(ModelId, LLMTransport)]  -- ^ models under test
  -> [TurnPrompt]
  -> SystemState               -- ^ baseline state
  -> IO ComparisonRun
runComparison runId mode models prompts ss0 = do
  t0 <- getCurrentTime
  outcomes <- mapM (runModelOutcomes mode ss0) models
  let globalIncidents = concatMap moTotalIncidentsList outcomes
  return ComparisonRun
    { crRunId         = runId
    , crTimestamp     = t0
    , crModelOutcomes = outcomes
    , crGlobalIncidents = globalIncidents
    }
  where
    sessionCount = 3 :: Int

    runModelOutcomes Sequential baseline (mid, transport) = do
      sessions <- mapM (\sid -> do
        (ss', results) <- runModelSession sid mid transport prompts baseline
        let incidents = detectIncidents mid results
        return (aggregateSession mid sid results) { soIncidents = incidents }
        ) [1..sessionCount]
      return (aggregateModel mid sessions)

    runModelOutcomes Interleaved baseline (mid, transport) = do
      sessions <- mapM (\sid -> do
        resultsMap <- runInterleavedSession sid [(mid, transport)] prompts baseline
        let results = case lookup mid resultsMap of
                        Just rs -> rs
                        Nothing -> []
            incidents = detectIncidents mid results
        return (aggregateSession mid sid results) { soIncidents = incidents }
        ) [1..sessionCount]
      return (aggregateModel mid sessions)

    moTotalIncidentsList mo = concatMap soIncidents (moSessions mo)

-- ---------------------------------------------------------------------------
-- Aggregation

-- | Aggregate a single session's turn results.
aggregateSession :: ModelId -> Int -> [TurnResult] -> SessionOutcome
aggregateSession modelId sessionId results =
  SessionOutcome
    { soModelId               = modelId
    , soSessionId             = sessionId
    , soTotalTurns            = length results
    , soSuccessCount          = countWhere isAccept
    , soTransportErrorCount   = countWhere isTransportError
    , soParseRejectCount      = countWhere isParseReject
    , soValidationRejectCount = countWhere isValidationReject
    , soSandboxRejectCount    = countWhere isSandboxReject
    , soSandboxAcceptCount    = countWhere isAccept
    , soTotalLatencyMs        = sum (map trLatencyMs results)
    , soIncidents             = []
    }
  where
    status r = ltValidationStatus (trTelemetry r)
    isAccept r       = status r == "accept"
    isTransportError r = case trOutcome r of
                           Left _  -> True
                           Right _ -> False
    isParseReject r      = status r == "invalid_response"
    isValidationReject r = status r == "validation_reject"
    isSandboxReject r    = status r == "sandbox_reject"
    countWhere p = length (filter p results)

-- | Aggregate across sessions for one model.
aggregateModel :: ModelId -> [SessionOutcome] -> ModelOutcome
aggregateModel modelId sessions =
  let totalTurns    = sum (map soTotalTurns sessions)
      totalSuccess  = sum (map soSuccessCount sessions)
      totalLatency  = sum (map soTotalLatencyMs sessions)
      totalTransportErrors = sum (map soTransportErrorCount sessions)
      totalParseRejects    = sum (map soParseRejectCount sessions)
      totalValRejects    = sum (map soValidationRejectCount sessions)
      totalValidatorChecks = max 0 (totalTurns - totalTransportErrors)
      totalSandboxChecks   = max 0 (totalValidatorChecks - totalParseRejects - totalValRejects)
      totalIncidents = sum (map (length . soIncidents) sessions)
  in ModelOutcome
    { moModelId              = modelId
    , moSessions             = sessions
    , moAvgSuccessRate       = rate totalSuccess totalTurns
    , moAvgLatencyMs         = rate totalLatency totalTurns
    , moAvgValidatorAcceptRate = rate totalSuccess totalValidatorChecks
    , moAvgSandboxPassRate     = rate totalSuccess totalSandboxChecks
    , moTotalIncidents       = totalIncidents
    }
  where
    rate _ 0 = 0.0
    rate n d = fromIntegral n / fromIntegral d

-- ---------------------------------------------------------------------------
-- Incident detection

detectIncidents :: ModelId -> [TurnResult] -> [ComparisonIncident]
detectIncidents modelId results =
  concat
    [ detectConsecutiveTransportErrors modelId results
    , detectConsecutiveValidatorRejects modelId results
    , detectConsecutiveSandboxRejects modelId results
    , detectRequestRejectLoops modelId results
    ]

-- | 3+ consecutive transport errors.
detectConsecutiveTransportErrors :: ModelId -> [TurnResult] -> [ComparisonIncident]
detectConsecutiveTransportErrors modelId results =
  map (\(i, len) -> IncidentConsecutiveTransportErrors modelId i len) $
  findConsecutive 3 (\r -> case trOutcome r of Left _ -> True; _ -> False) results

-- | 5+ consecutive validator-level rejects (transport, parse, validation).
detectConsecutiveValidatorRejects :: ModelId -> [TurnResult] -> [ComparisonIncident]
detectConsecutiveValidatorRejects modelId results =
  map (\(i, len) -> IncidentConsecutiveValidatorRejects modelId i len) $
  findConsecutive 5 (\r ->
    let s = ltValidationStatus (trTelemetry r)
    in s `elem` ["transport_error", "invalid_response", "validation_reject"]
  ) results

-- | 3+ consecutive sandbox rejects with the *same* degradation tag.
detectConsecutiveSandboxRejects :: ModelId -> [TurnResult] -> [ComparisonIncident]
detectConsecutiveSandboxRejects modelId results =
  concatMap (\(i, len, tag) -> [IncidentConsecutiveSandboxRejects modelId i tag len]) $
  findConsecutiveWithSameReason 3 isSandboxReject getSandboxReason results
  where
    isSandboxReject r = ltValidationStatus (trTelemetry r) == "sandbox_reject"
    getSandboxRejectReason r = ltRejectReason (trTelemetry r)
    getSandboxReason r =
      if isSandboxReject r
        then getSandboxRejectReason r
        else Nothing

-- | Repeated request->reject loop without new grafts.
-- Simplified: 5+ consecutive turns where graft is Nothing and status /= accept.
detectRequestRejectLoops :: ModelId -> [TurnResult] -> [ComparisonIncident]
detectRequestRejectLoops modelId results =
  map (\(_i, len) -> IncidentRequestRejectLoop modelId len) $
  findConsecutive 5 (\r ->
    ltGraftTurn (trTelemetry r) == Nothing && ltValidationStatus (trTelemetry r) /= "accept"
  ) results

-- | Find runs of at least @minLen@ elements satisfying predicate @p@.
-- Returns 1-based (startIndex, runLength).
findConsecutive :: Int -> (a -> Bool) -> [a] -> [(Int, Int)]
findConsecutive minLen p = go 1
  where
    go _ [] = []
    go i xs@(y:_) =
      if p y
        then let (run, rest) = span p xs
                 len = length run
             in if len >= minLen
                  then (i, len) : go (i + len) rest
                  else go (i + len) rest
        else go (i + 1) (drop 1 xs)
    go _ _ = []

-- | Like 'findConsecutive' but also requires the same 'Just' reason.
findConsecutiveWithSameReason :: Int -> (a -> Bool) -> (a -> Maybe Text) -> [a] -> [(Int, Int, Text)]
findConsecutiveWithSameReason minLen p getR = go 1
  where
    go _ [] = []
    go i xs@(y:_) =
      if p y
        then case getR y of
               Just r0 -> let (run, rest) = span (\z -> p z && getR z == Just r0) xs
                              len = length run
                          in if len >= minLen
                               then (i, len, r0) : go (i + len) rest
                               else go (i + len) rest
               Nothing -> go (i + 1) (drop 1 xs)
        else go (i + 1) (drop 1 xs)
    go _ _ = []

-- ---------------------------------------------------------------------------
-- Rendering

-- | Render a comparison run as markdown-like telemetry text.
renderComparisonRun :: ComparisonRun -> Text
renderComparisonRun cr =
  T.concat
    [ "# Model Comparison Run: ", crRunId cr, "\n"
    , "Timestamp: ", T.pack (show (crTimestamp cr)), "\n"
    , "Models: ", T.pack (show (length (crModelOutcomes cr))), "\n"
    , "Global incidents: ", T.pack (show (length (crGlobalIncidents cr))), "\n"
    , T.concat (map renderModelOutcome (crModelOutcomes cr))
    ]

renderModelOutcome :: ModelOutcome -> Text
renderModelOutcome mo =
  T.concat
    [ "\n## ", moModelId mo, "\n"
    , "- Sessions: ", T.pack (show (length (moSessions mo))), "\n"
    , "- Avg success rate: ", T.pack (show (moAvgSuccessRate mo)), "\n"
    , "- Avg latency (ms/turn): ", T.pack (show (moAvgLatencyMs mo)), "\n"
    , "- Validator accept rate: ", T.pack (show (moAvgValidatorAcceptRate mo)), "\n"
    , "- Sandbox pass rate: ", T.pack (show (moAvgSandboxPassRate mo)), "\n"
    , "- Total incidents: ", T.pack (show (moTotalIncidents mo)), "\n"
    ]
