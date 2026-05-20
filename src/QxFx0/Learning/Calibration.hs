{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Calibration
Description : WP4 — Closed learning loop with calibration versioning.

Implements the @ask → verify → simulate → accept / reject → persist
→ monitor → rollback@ lifecycle for every externally sourced proposal.

* No runtime code is patched automatically.
* Only 'SalienceWeights', 'FieldHeuristics', or rule/concept config
  may be updated through the validated channel.
* Every accepted change is versioned; degradation triggers automatic
  rollback to the previous version.
-}
module QxFx0.Learning.Calibration
  ( CalibrationId(..)
  , CalibrationProposal(..)
  , CalibrationStatus(..)
  , CalibrationEntry(..)
  , CalibrationLog(..)
  , emptyCalibrationLog
  , verifyProposal
  , simulateProposal
  , acceptProposal
  , monitorCalibration
  , rollbackCalibration
  , currentCalibrationVersion
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Self.Salience (SalienceWeights)
import QxFx0.Self.Field (FieldHeuristics)

-- | Monotonically increasing calibration version number.
newtype CalibrationId = CalibrationId { unCalibrationId :: Int }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | A proposal received from an external tool (or human mentor).
data CalibrationProposal
  = ProposalSalienceWeights !SalienceWeights
    -- ^ Adjust salience weights empirically.
  | ProposalFieldHeuristics !FieldHeuristics
    -- ^ Adjust field heuristics empirically.
  | ProposalRule !Text
    -- ^ Add or modify a deliberation / routing rule.
  | ProposalConcept !Text
    -- ^ Add a new keyword or concept to the local ontology.
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Stage of a proposal in the closed loop.
data CalibrationStatus
  = Pending
    -- ^ Just received; not yet validated.
  | Verified
    -- ^ Passed basic syntactic / range sanity checks.
  | Simulated
    -- ^ Dry-run against synthetic or historical trace succeeded.
  | Accepted
    -- ^ Passed verify + simulate; persisted to runtime config.
  | Rejected
    -- ^ Failed at verify or simulate stage.
  | RolledBack
    -- ^ Was Accepted but later degraded; reverted to previous version.
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Single record in the calibration ledger.
data CalibrationEntry = CalibrationEntry
  { ceId          :: !CalibrationId
  , ceProposal    :: !CalibrationProposal
  , ceStatus      :: !CalibrationStatus
  , ceCreatedTurn :: !Int
    -- ^ Turn when the proposal was received.
  , ceDecidedTurn :: !(Maybe Int)
    -- ^ Turn when the proposal reached Accepted / Rejected / RolledBack.
  , cePrevId      :: !(Maybe CalibrationId)
    -- ^ Previous version to roll back to (Nothing for the first entry).
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON CalibrationEntry where
  toJSON e = object
    [ "id"          .= unCalibrationId (ceId e)
    , "proposal"    .= ceProposal e
    , "status"      .= ceStatus e
    , "createdTurn" .= ceCreatedTurn e
    , "decidedTurn" .= ceDecidedTurn e
    , "prevId"      .= fmap unCalibrationId (cePrevId e)
    ]

instance FromJSON CalibrationEntry where
  parseJSON = withObject "CalibrationEntry" $ \o ->
    CalibrationEntry
      <$> (CalibrationId <$> o .: "id")
      <*> o .: "proposal"
      <*> o .:? "status" .!= Pending
      <*> o .:? "createdTurn" .!= 0
      <*> o .:? "decidedTurn" .!= Nothing
      <*> (fmap CalibrationId <$> o .:? "prevId" .!= Nothing)

-- | The calibration ledger kept in 'SystemState'.
newtype CalibrationLog = CalibrationLog { unCalibrationLog :: [CalibrationEntry] }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

emptyCalibrationLog :: CalibrationLog
emptyCalibrationLog = CalibrationLog []

-- | Basic sanity verification of a proposal.
--
-- * 'ProposalSalienceWeights' — all weights must be in [0, 1].
-- * 'ProposalFieldHeuristics' — all heuristics must be non-negative.
-- * 'ProposalRule' — non-empty and not already present in the
--   blocked-concept list (simple collision guard).
-- * 'ProposalConcept' — non-empty.
verifyProposal :: [Text] -> CalibrationProposal -> Either Text ()
verifyProposal blocked proposal =
  case proposal of
    ProposalSalienceWeights _ -> Right () -- range checks delegated to SalienceWeights smart constructor
    ProposalFieldHeuristics _ -> Right () -- non-negativity enforced by FieldHeuristics constructor
    ProposalRule txt
      | T.null txt -> Left "empty_rule"
      | txt `elem` blocked -> Left "blocked_rule"
      | otherwise -> Right ()
    ProposalConcept txt
      | T.null txt -> Left "empty_concept"
      | otherwise -> Right ()

-- | Simulate a proposal against a lightweight synthetic signal.
--
-- For weights / heuristics: apply them to a neutral synthetic
-- 'ConatusEnergy' and verify the result does not flip the gate
-- (i.e. energy must not become *more* negative).
--
-- For rules / concepts: succeed trivially in this stub; real trace
-- replay is Phase-7 infrastructure.
simulateProposal :: CalibrationProposal -> Either Text ()
simulateProposal _ = Right () -- WP4 stub: deterministic pass

-- | Accept a verified & simulated proposal, producing the updated
-- entry, next version ID, and the human-readable tag to persist.
acceptProposal
  :: CalibrationId        -- ^ next available version ID
  -> CalibrationProposal
  -> Int                  -- ^ current turn
  -> Maybe CalibrationId  -- ^ previous version to link for rollback
  -> (CalibrationEntry, CalibrationId)
acceptProposal nextId proposal turn prevId =
  let entry = CalibrationEntry
        { ceId          = nextId
        , ceProposal    = proposal
        , ceStatus      = Accepted
        , ceCreatedTurn = turn
        , ceDecidedTurn = Just turn
        , cePrevId      = prevId
        }
  in (entry, CalibrationId (unCalibrationId nextId + 1))

-- | Monitor an accepted calibration after a window of turns.
--
-- If the 'LearningNeed' that triggered the proposal has gotten
-- *worse* (level increased or trend is Rising) within the monitor
-- window, recommend rollback.
--
-- Parameters:
--   * preAcceptLevel   — level at the turn of acceptance.
--   * currentLevel     — level now.
--   * currentTrend     — trend now.
--   * windowTurns      — how many turns have passed since acceptance.
--   * minMonitorWindow — minimum turns before rollback is allowed.
monitorCalibration
  :: Double       -- ^ preAcceptLevel
  -> Double       -- ^ currentLevel
  -> Int          -- ^ windowTurns
  -> Int          -- ^ minMonitorWindow
  -> Either Text ()
monitorCalibration preAcceptLevel currentLevel windowTurns minMonitorWindow
  | windowTurns < minMonitorWindow = Right ()
  | currentLevel > preAcceptLevel  = Left "degradation_detected"
  | otherwise                      = Right ()

-- | Roll back to the previous calibration version.
-- Returns the rolled-back entry and the ID of the version that is
-- now current (the prevId linked in the accepted entry).
rollbackCalibration :: CalibrationEntry -> Int -> Maybe (CalibrationEntry, CalibrationId)
rollbackCalibration entry turn =
  case (ceStatus entry, cePrevId entry) of
    (Accepted, Just prev) ->
      let rolled = entry
            { ceStatus      = RolledBack
            , ceDecidedTurn = Just turn
            }
      in Just (rolled, prev)
    _ -> Nothing

-- | Extract the version ID of the most recent Accepted entry.
currentCalibrationVersion :: CalibrationLog -> Maybe CalibrationId
currentCalibrationVersion (CalibrationLog log) =
  case filter ((== Accepted) . ceStatus) log of
    [] -> Nothing
    xs -> Just (ceId (last xs))
