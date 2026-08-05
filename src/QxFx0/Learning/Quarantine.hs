{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Learning.Quarantine
  ( QuarantineReason(..)
  , QuarantineEntry(..)
  , entryReasonText
  , provenanceText
  , relationTypeText
  , sha256Hex
  , ensureQuarantineSchema
  , recordQuarantine
  , recordQuarantinesOnConnection
  , trimQuarantine
  ) where

import Control.DeepSeq (NFData)
import Crypto.Hash.SHA256 (hash)
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.ByteString as BS
import Data.Bits ((.&.), shiftR)
import Data.Char (intToDigit)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import GHC.Generics (Generic)

import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import QxFx0.Bridge.TxStatement
  ( TxStmt
  , bindDoubleOrFail
  , bindInt64OrFail
  , bindTextOrFail
  , prepareTx
  , stepOrFail
  )
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types (EdgeProvenance(..))

data QuarantineReason
  = QRContradiction
  | QRLowerAuthorityConflict
  | QRSameAuthorityReplaced
  | QRRelationConflict
  | QRParseFailure
  | QRCircuitOpenDrop
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

entryReasonText :: QuarantineReason -> Text
entryReasonText QRContradiction = "contradiction"
entryReasonText QRLowerAuthorityConflict = "lower_authority_conflict"
entryReasonText QRSameAuthorityReplaced = "same_authority_replaced"
entryReasonText QRRelationConflict = "relation_conflict"
entryReasonText QRParseFailure = "parse_failure"
entryReasonText QRCircuitOpenDrop = "circuit_open_drop"

data QuarantineEntry = QuarantineEntry
  { qeTimestamp        :: !UTCTime
  , qeTurnSeq          :: !(Maybe Int)
  , qeRequestId        :: !Text
  , qeTopic            :: !Text
  , qeEdgeFrom         :: !Text
  , qeEdgeTo           :: !Text
  , qeEdgeProvenance   :: !EdgeProvenance
  , qeEdgeRelationType :: !(Maybe Text)
  , qeEdgeConfidence   :: !Double
  , qeConflictingFrom  :: !(Maybe Text)
  , qeConflictingTo    :: !(Maybe Text)
  , qeConflictingProv  :: !(Maybe Text)
  , qeReason           :: !QuarantineReason
  , qeSource           :: !Text
  , qePromptHash       :: !(Maybe Text)
  , qeResponseHash     :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

provenanceText :: EdgeProvenance -> Text
provenanceText ProvenanceCurated = "curated"
provenanceText ProvenanceCorpus = "corpus"
provenanceText ProvenanceSubstrate = "substrate"
provenanceText ProvenanceIngested = "ingested"
provenanceText ProvenanceRuntimeLLM = "runtime_llm"
provenanceText ProvenanceSelfPlay = "selfplay"
provenanceText ProvenanceDialogueFeedback = "dialogue_feedback"
provenanceText ProvenanceHumanCorrection = "human_correction"
provenanceText ProvenanceDerived = "derived"

-- | Convert a relation type to its canonical snake_case database text.
relationTypeText :: RelationType -> Text
relationTypeText = T.toLower . T.intercalate "_" . splitCamel . T.drop 3 . T.pack . show
  where
    splitCamel :: Text -> [Text]
    splitCamel = go []
      where
        go acc txt
          | T.null txt = reverse acc
          | otherwise  =
              let (word, rest) = T.span isLowerRest (T.drop 1 txt)
                  first = T.take 1 txt
              in go (T.toLower (first <> word) : acc) rest
        isLowerRest c = c `elem` ['a'..'z'] || c `elem` ['0'..'9']

sha256Hex :: BS.ByteString -> Text
sha256Hex = T.pack . concatMap byteHex . BS.unpack . hash
  where
    byteHex w = [intToDigit (fromIntegral ((w `shiftR` 4) .&. 0x0f)), intToDigit (fromIntegral (w .&. 0x0f))]

ensureQuarantineSchema :: QxFx0DB -> IO ()
ensureQuarantineSchema db = do
  result <- withDB (qdbPath db) $ \conn -> do
    schema <- prepareTx conn "ensure_quarantine_schema"
      "CREATE TABLE IF NOT EXISTS quarantine (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, turn_seq INTEGER, request_id TEXT NOT NULL, topic TEXT NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, edge_provenance TEXT NOT NULL, edge_relation_type TEXT, edge_confidence REAL NOT NULL, conflicting_from TEXT, conflicting_to TEXT, conflicting_provenance TEXT, reason TEXT NOT NULL, source TEXT NOT NULL, prompt_hash TEXT, response_hash TEXT)"
    stepOrFail schema
    idxTs <- prepareTx conn "ensure_quarantine_idx_ts"
      "CREATE INDEX IF NOT EXISTS idx_quarantine_ts ON quarantine(ts)"
    stepOrFail idxTs
    idxTopic <- prepareTx conn "ensure_quarantine_idx_topic"
      "CREATE INDEX IF NOT EXISTS idx_quarantine_topic ON quarantine(topic)"
    stepOrFail idxTopic
  either (fail . T.unpack) pure result

recordQuarantine :: QxFx0DB -> QuarantineEntry -> IO ()
recordQuarantine db entry = do
  result <- withDB (qdbPath db) $ \conn -> recordQuarantinesOnConnection conn [entry]
  either (fail . T.unpack) pure result

-- | Append quarantine records through a caller-owned transaction.
recordQuarantinesOnConnection :: NSQL.Database -> [QuarantineEntry] -> IO ()
recordQuarantinesOnConnection _ [] = pure ()
recordQuarantinesOnConnection conn entries = do
  mapM_ (insertQuarantineOnConnection conn) entries
  trimQuarantineConn conn 10000

insertQuarantineOnConnection :: NSQL.Database -> QuarantineEntry -> IO ()
insertQuarantineOnConnection conn entry = do
  stmt <- prepareTx conn "insert_quarantine"
    "INSERT INTO quarantine (ts, turn_seq, request_id, topic, edge_from, edge_to, edge_provenance, edge_relation_type, edge_confidence, conflicting_from, conflicting_to, conflicting_provenance, reason, source, prompt_hash, response_hash) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  bindInt64OrFail stmt 1 (utcMicros (qeTimestamp entry))
  bindMaybeInt stmt 2 (qeTurnSeq entry)
  bindTextOrFail stmt 3 (qeRequestId entry)
  bindTextOrFail stmt 4 (qeTopic entry)
  bindTextOrFail stmt 5 (qeEdgeFrom entry)
  bindTextOrFail stmt 6 (qeEdgeTo entry)
  bindTextOrFail stmt 7 (provenanceText (qeEdgeProvenance entry))
  bindMaybeText stmt 8 (qeEdgeRelationType entry)
  bindDoubleOrFail stmt 9 (qeEdgeConfidence entry)
  bindMaybeText stmt 10 (qeConflictingFrom entry)
  bindMaybeText stmt 11 (qeConflictingTo entry)
  bindMaybeText stmt 12 (qeConflictingProv entry)
  bindTextOrFail stmt 13 (entryReasonText (qeReason entry))
  bindTextOrFail stmt 14 (qeSource entry)
  bindMaybeText stmt 15 (qePromptHash entry)
  bindMaybeText stmt 16 (qeResponseHash entry)
  stepOrFail stmt

trimQuarantine :: QxFx0DB -> Int -> IO ()
trimQuarantine db cap = do
  result <- withDB (qdbPath db) $ \conn -> trimQuarantineConn conn cap
  either (fail . T.unpack) pure result

trimQuarantineConn :: NSQL.Database -> Int -> IO ()
trimQuarantineConn conn cap = do
  stmt <- prepareTx conn "trim_quarantine"
    "DELETE FROM quarantine WHERE id IN (SELECT id FROM quarantine ORDER BY ts DESC, id DESC LIMIT -1 OFFSET ?)"
  bindInt64OrFail stmt 1 (fromIntegral (max 0 cap))
  stepOrFail stmt

bindMaybeText :: TxStmt -> Int -> Maybe Text -> IO ()
bindMaybeText stmt ix = bindTextOrFail stmt (fromIntegral ix) . maybe "" id

bindMaybeInt :: TxStmt -> Int -> Maybe Int -> IO ()
bindMaybeInt stmt ix = bindInt64OrFail stmt (fromIntegral ix) . maybe 0 fromIntegral

utcMicros :: UTCTime -> Int64
utcMicros = round . (* 1000000) . realToFrac . utcTimeToPOSIXSeconds
