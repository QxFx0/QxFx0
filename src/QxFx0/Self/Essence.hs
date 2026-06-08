{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{- |

Phase 9 essence selection infrastructure.

Reads the system's deliberation history and accumulates an
'EssenceTrajectory' from which a later 'commit' will produce an
irrevocable 'EssenceCommitment'. Pure and total.

See @docs\/adr\/0012-essence-commitment.md@ for the architecture
and @docs\/phase-9-essence-implementation-spec.md@ for the
contract that produced this module.

This module is /not/ a model of phenomenal selfhood. It is a
structural accumulator over the right- and left-hemispheric
verdicts already produced by 'QxFx0.Self.Deliberation'. The
forcing dynamics (Phase 10) live behind a feature flag; until
then, every essence remains 'EssenceUncommitted'.
-}
module QxFx0.Self.Essence
  ( -- * Carriers
    Essence (..)
  , EssenceTrajectory (..)
  , EssenceWitness (..)
  , FieldSignature (..)
  , FieldBand (..)
  , ValenceBand (..)
  , TrajectoryHash (..)
    -- * Modes and triggers
  , EssenceMode (..)
  , CommitmentTrigger (..)
  , EssenceCommitment (..)
    -- * Violations and validation (Phase 10)
  , EssenceViolation (..)
  , validatePlan
  , renderEssenceViolation
  , admissibleFamilies
  , admissibleTones
  , admissibleStyles
    -- * Modulation
  , EssenceModulation (..)
  , defaultEssenceModulation
  , phase9EssenceModulation
    -- * Pure morphisms
  , emptyEssence
  , emptyTrajectory
  , witness
  , shouldCommit
  , extractMode
  , commit
    -- * Renderers (snake_case, JSON-schema-stable)
  , renderEssenceMode
  , renderCommitmentTrigger
    -- * Field signature
  , fieldSignature
  ) where

import Control.DeepSeq (NFData)
import qualified Crypto.Hash.SHA256 as SHA256
import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), encode)
import Data.Aeson.Types (typeMismatch)
import qualified Data.ByteString as BS
import Data.Foldable (foldl', toList)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Numeric (showHex)

import QxFx0.Self.Conatus (ConatusEnergy (..))
import QxFx0.Self.Deliberation
  ( Agreement (..)
  , Deliberation (..)
  , DeliberationTrace (..)
  , NarrativeTone (..)
  , Plan (..)
  , ReconcileRule (..)
  )
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Consolidation (..)
  , Counterfactual (..)
  , Field (..)
  , FieldConfidence (..)
  , Resonance (..)
  )
import QxFx0.Self.Salience (SalienceDriver (..))
import QxFx0.Types.Decision.Enums.Render (RenderStyle (..))
import QxFx0.Types.Domain (CanonicalMoveFamily (..))

-- ---------------------------------------------------------------------------
-- Carriers
-- ---------------------------------------------------------------------------

data Essence
  = EssenceUncommitted !EssenceTrajectory
  | EssenceCommitted   !EssenceTrajectory !EssenceCommitment
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceTrajectory = EssenceTrajectory
  { etWitnesses    :: !(Seq EssenceWitness)
  , etAngstLevel   :: !Double
  , etConatusFloor :: !Double
  , etCapacity     :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceWitness = EssenceWitness
  { ewTurnOrdinal     :: !Int
  , ewSalienceDriver  :: !SalienceDriver
  , ewReconcileRule   :: !ReconcileRule
  , ewAgreement       :: !Agreement
  , ewDivergence      :: !Double
  , ewConatusScalar   :: !Double
  , ewFieldSignature  :: !FieldSignature
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Field signature
-- ---------------------------------------------------------------------------

data FieldSignature = FieldSignature
  { fsResonance      :: !FieldBand
  , fsArousal        :: !FieldBand
  , fsValence        :: !ValenceBand
  , fsConsolidation  :: !FieldBand
  , fsCounterfactual :: !FieldBand
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data FieldBand
  = BandLow
  | BandMid
  | BandHigh
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data ValenceBand
  = ValenceNegative
  | ValenceNeutral
  | ValencePositive
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Coarse hash of a 'Field' into a 'FieldSignature' for
-- trajectory storage. Components in [0, 1] bucket at
-- @bandLow / bandHigh@; valence in [-1, 1] buckets at
-- @valenceLowEdge / valenceHighEdge@.
fieldSignature :: EssenceModulation -> Field -> FieldSignature
fieldSignature em f = FieldSignature
  { fsResonance      = bucketUnit (emBandLowEdge em) (emBandHighEdge em) (unResonance       (fieldResonance      f))
  , fsArousal        = bucketUnit (emBandLowEdge em) (emBandHighEdge em) (atmosphereArousal (fieldAtmosphere     f))
  , fsValence        = bucketValence (emValenceLowEdge em) (emValenceHighEdge em) (atmosphereValence (fieldAtmosphere f))
  , fsConsolidation  = bucketUnit (emBandLowEdge em) (emBandHighEdge em) (unConsolidation   (fieldConsolidation  f))
  , fsCounterfactual = bucketUnit (emBandLowEdge em) (emBandHighEdge em) (unCounterfactual  (fieldCounterfactual f))
  }
  where
    bucketUnit lo hi x
      | x < lo    = BandLow
      | x > hi    = BandHigh
      | otherwise = BandMid
    bucketValence lo hi x
      | x < lo    = ValenceNegative
      | x > hi    = ValencePositive
      | otherwise = ValenceNeutral

-- ---------------------------------------------------------------------------
-- Modes and triggers
-- ---------------------------------------------------------------------------

data EssenceMode
  = EssenceWitnessing      -- pre-commitment, runtime-visible
  | EssenceContemplative
  | EssenceDialogical
  | EssenceIntegrative
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data CommitmentTrigger
  = TriggerAngstThreshold
  | TriggerConatusErosion
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

newtype TrajectoryHash = TrajectoryHash { unTrajectoryHash :: Text }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Emit a BARE string, matching the 'String' case the FromJSON below accepts.
-- The generic newtype ToJSON would emit @{"unTrajectoryHash":...}@ (an Object),
-- which the hand-written FromJSON rejects — so @decode . encode@ failed on the
-- persisted @selfEssence.ecWitnessHash@ path. (Class II round-trip fix.)
instance ToJSON TrajectoryHash where
  toJSON = toJSON . unTrajectoryHash

instance FromJSON TrajectoryHash where
  parseJSON value =
    case value of
      String txt -> pure (TrajectoryHash txt)
      Number n ->
        let rounded = round n :: Integer
        in if fromInteger rounded == n
             then pure (TrajectoryHash (T.pack (show rounded)))
             else pure (TrajectoryHash (T.pack (show (realToFrac n :: Double))))
      _ -> typeMismatch "TrajectoryHash" value

data EssenceCommitment = EssenceCommitment
  { ecMode         :: !EssenceMode
  , ecTrigger      :: !CommitmentTrigger
  , ecCommittedAt  :: !Int                -- turn ordinal
  , ecWitnessHash  :: !TrajectoryHash
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Modulation
-- ---------------------------------------------------------------------------

data EssenceModulation = EssenceModulation
  { emAngstCommitmentThreshold     :: !Double  -- [0, 1]
  , emAngstAccrualRate             :: !Double  -- per qualifying turn
  , emAngstDecayRate               :: !Double  -- per agreement turn
  , emAngstAccrualDivergenceFloor  :: !Double  -- below floor no accrual
  , emConatusFloorWindow           :: !Int     -- turns of sub-floor
  , emConatusStructuralFloor       :: !Double  -- below which we count
  , emTrajectoryCapacity           :: !Int     -- ring-buffer length
    -- field-band bucketing knobs
  , emBandLowEdge                  :: !Double  -- below = BandLow
  , emBandHighEdge                 :: !Double  -- above = BandHigh
  , emValenceLowEdge               :: !Double  -- below = ValenceNegative
  , emValenceHighEdge              :: !Double  -- above = ValencePositive
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Original Phase 9 defaults, kept for backward-compat regression
-- locks.  Note: @emConatusStructuralFloor = 0.5@ was a unit-mismatch
-- error (calibrated against @arbitraryUnitDouble@ generators in
-- 'Test.Suite.SelfEssence', not the production runtime where
-- 'ceScalar' lives in log-scale [~5, ~20+]).  See ADR-0012 §15.1.
phase9EssenceModulation :: EssenceModulation
phase9EssenceModulation = EssenceModulation
  { emAngstCommitmentThreshold    = 0.75
  , emAngstAccrualRate            = 0.05
  , emAngstDecayRate              = 0.02
  , emAngstAccrualDivergenceFloor = 0.5
  , emConatusFloorWindow          = 8
  , emConatusStructuralFloor      = 0.5
  , emTrajectoryCapacity          = 32
  , emBandLowEdge                 = 0.33
  , emBandHighEdge                = 0.67
  , emValenceLowEdge              = -0.33
  , emValenceHighEdge             = 0.33
  }

-- | Calibrated defaults (post-Phase 10 §4).
--
-- * @emConatusStructuralFloor@ raised from 0.5 to 7.0 to match the
--   production codomain of 'computeConatusEnergy' (log-scale
--   unbounded, healthy range ~14-15).  See ADR-0012 §15.1.
-- * Angst-side parameters remain at Phase 9 values because the
--   synthetic long-session corpus could not reliably produce
--   'RuleHolisticAdvantage' / 'RuleFormalAdvantage' with
--   sufficient divergence.  Calibration deferred.  See ADR-0012 §15.2.
defaultEssenceModulation :: EssenceModulation
defaultEssenceModulation = phase9EssenceModulation
  { emConatusStructuralFloor = 7.0 }

-- ---------------------------------------------------------------------------
-- Constructors
-- ---------------------------------------------------------------------------

-- | The carrier-empty value. Used in 'Bootstrap' and in any test
-- harness that hand-builds a 'SystemState'.
emptyEssence :: Essence
emptyEssence = EssenceUncommitted emptyTrajectory

-- | The carrier-empty trajectory. @etAngstLevel = 0@,
-- @etConatusFloor = 1@ (so the floor only descends with witnessed
-- evidence), capacity from 'defaultEssenceModulation'.
emptyTrajectory :: EssenceTrajectory
emptyTrajectory = EssenceTrajectory
  { etWitnesses    = Seq.empty
  , etAngstLevel   = 0.0
  , etConatusFloor = 1.0
  , etCapacity     = emTrajectoryCapacity defaultEssenceModulation
  }

-- ---------------------------------------------------------------------------
-- Pure morphisms
-- ---------------------------------------------------------------------------

-- | Ingest one turn's deliberation into the trajectory.
--
-- Effects:
--
-- 1. Append a new 'EssenceWitness' to 'etWitnesses', truncating
--    the front to keep length ≤ 'etCapacity'.
-- 2. Update 'etAngstLevel':
--      * RuleConatusOverride       → no change.
--      * FullAgreement, divergence 0 → decay by 'emAngstDecayRate'.
--      * RuleHolisticAdvantage/RuleFormalAdvantage with
--        divergence ≥ 'emAngstAccrualDivergenceFloor'
--                              → accrue by 'emAngstAccrualRate'.
--      * otherwise (RuleSalienceLead, RuleTiedFallback,
--        sub-floor divergence)
--                              → no change.
--    Clamp to @[0, 1]@.
-- 3. Update 'etConatusFloor' to @min etConatusFloor ceScalar@.
witness
  :: EssenceModulation
  -> Int          -- turn ordinal
  -> ConatusEnergy
  -> Field
  -> Deliberation
  -> EssenceTrajectory
  -> EssenceTrajectory
witness em turnOrdinal ce field deliberation traj =
  let sig     = fieldSignature em field
      witness_ = EssenceWitness
        { ewTurnOrdinal     = turnOrdinal
        , ewSalienceDriver  = dtSalienceDriver (delibTrace deliberation)
        , ewReconcileRule   = dtRule (delibTrace deliberation)
        , ewAgreement       = dtAgreement (delibTrace deliberation)
        , ewDivergence      = dtDivergence (delibTrace deliberation)
        , ewConatusScalar   = ceScalar ce
        , ewFieldSignature  = sig
        }
      newWitnesses = trimSeq (etCapacity traj) (etWitnesses traj Seq.|> witness_)
      newAngst = clampUnit $ case dtRule (delibTrace deliberation) of
        RuleConatusOverride -> etAngstLevel traj
        RuleAgreement
          | dtDivergence (delibTrace deliberation) == 0.0
          -> max 0.0 (etAngstLevel traj - emAngstDecayRate em)
        RuleHolisticAdvantage
          | dtDivergence (delibTrace deliberation) >= emAngstAccrualDivergenceFloor em
          -> min 1.0 (etAngstLevel traj + emAngstAccrualRate em)
        RuleFormalAdvantage
          | dtDivergence (delibTrace deliberation) >= emAngstAccrualDivergenceFloor em
          -> min 1.0 (etAngstLevel traj + emAngstAccrualRate em)
        _ -> etAngstLevel traj
      newFloor = min (etConatusFloor traj) (ceScalar ce)
  in traj
       { etWitnesses    = newWitnesses
       , etAngstLevel   = newAngst
       , etConatusFloor = newFloor
       }
  where
    trimSeq cap sq
      | Seq.length sq > cap = case Seq.viewl sq of
          Seq.EmptyL  -> sq
          (_ Seq.:< rest) -> trimSeq cap rest
      | otherwise = sq

-- | Returns 'Just' when the trajectory has crossed a commitment
-- threshold. Priority: 'TriggerAngstThreshold' over
-- 'TriggerConatusErosion' (see §0 Q2 of the spec).
--
-- Conatus erosion triggers when *every one* of the last
-- 'emConatusFloorWindow' witnessed turns has 'ewConatusScalar'
-- below 'emConatusStructuralFloor' (true sliding window, Phase 10).
-- The 'etConatusFloor' field is retained for diagnostics and trace
-- but is no longer the trigger signal.
shouldCommit :: EssenceModulation -> EssenceTrajectory -> Maybe CommitmentTrigger
shouldCommit em traj =
  let angstFires = etAngstLevel traj >= emAngstCommitmentThreshold em
      window     = emConatusFloorWindow em
      ws         = etWitnesses traj
      lastN      = Seq.drop (max 0 (Seq.length ws - window)) ws
      enoughWits = Seq.length lastN >= window
      allSubFloor =
        enoughWits
          && all (\w -> ewConatusScalar w < emConatusStructuralFloor em) lastN
  in case (angstFires, allSubFloor) of
       (True,  _)    -> Just TriggerAngstThreshold
       (False, True) -> Just TriggerConatusErosion
       _             -> Nothing

-- | Deterministic mode extraction.  Never returns
-- 'EssenceWitnessing'.  Selection rule:
--
-- @
--   let n = length etWitnesses
--       aRate = #{Agreement = FullAgreement} / n
--       hRate = #{ReconcileRule = RuleHolisticAdvantage} / n
--       fRate = #{ReconcileRule = RuleFormalAdvantage}   / n
--   in case maxBy snd
--        [(EssenceIntegrative,   aRate)
--        ,(EssenceDialogical,    hRate)
--        ,(EssenceContemplative, fRate)] of
--        (m, r) | r > 0     -> m
--               | otherwise -> EssenceContemplative   -- tie-break
-- @
--
-- The tie-break is 'EssenceContemplative' because, in the absence
-- of any signal, the formal hemisphere is the safer default
-- (lower behavioural divergence post-commit).
extractMode :: EssenceTrajectory -> EssenceMode
extractMode traj =
  let ws = etWitnesses traj
      n  = fromIntegral (Seq.length ws) :: Double
      counts = foldl' tally (0, 0, 0) ws
      (aCount, hCount, fCount) = counts
      aRate = if n > 0 then fromIntegral aCount / n else 0.0
      hRate = if n > 0 then fromIntegral hCount / n else 0.0
      fRate = if n > 0 then fromIntegral fCount / n else 0.0
      candidates =
        [ (EssenceIntegrative,   aRate)
        , (EssenceDialogical,    hRate)
        , (EssenceContemplative, fRate)
        ]
      (bestMode, bestRate) = maximumBySnd candidates
  in if bestRate > 0.0 then bestMode else EssenceContemplative
  where
    tally (a, h, f) w =
      case (ewAgreement w, ewReconcileRule w) of
        (Agree, _)            -> (a + 1, h, f)
        (_, RuleHolisticAdvantage) -> (a, h + 1, f)
        (_, RuleFormalAdvantage)   -> (a, h, f + 1)
        _                   -> (a, h, f)
    maximumBySnd [] = (EssenceContemplative, 0.0)
    maximumBySnd (x:xs) = foldl' pick x xs
      where
        pick acc@(_, va) y@(_, vb) = if vb > va then y else acc

-- | Construct the commitment.  Total over trajectories that have
-- passed 'shouldCommit'; technically total over all trajectories
-- but used only when 'shouldCommit' returned 'Just'.  The hash is
-- a simple structural fold over the 'etWitnesses' sequence —
-- enough to detect tampering across replay, not a cryptographic
-- guarantee.
commit
  :: Int                -- current turn ordinal
  -> CommitmentTrigger
  -> EssenceTrajectory
  -> EssenceCommitment
commit turnOrdinal trigger traj =
  EssenceCommitment
    { ecMode        = extractMode traj
    , ecTrigger     = trigger
    , ecCommittedAt = turnOrdinal
    , ecWitnessHash = TrajectoryHash (sha256Witnesses (toList (etWitnesses traj)))
    }
  where
    sha256Witnesses witnesses =
      "sha256:" <> T.pack (concatMap byteToHex (BS.unpack (SHA256.hashlazy (encode witnesses))))
    byteToHex byte =
      let raw = showHex byte ""
      in case raw of
           [single] -> ['0', single]
           other -> other

-- ---------------------------------------------------------------------------
-- Post-commitment validation (Phase 10)
-- ---------------------------------------------------------------------------

-- | A commitment violation.  Priority order: family → tone → style;
-- the first mismatch is the one reported.
data EssenceViolation
  = ViolationFamilyMismatch !EssenceMode !CanonicalMoveFamily
  | ViolationToneMismatch   !EssenceMode !NarrativeTone
  | ViolationStyleMismatch  !EssenceMode !RenderStyle
  | ViolationMissingDeliberation !EssenceMode
    -- ^ A committed essence cannot be validated without a reconciled
    --   plan. Missing deliberation is therefore a fail-closed state,
    --   not an implicit validation pass.
  | ViolationRefusedCommitment !CommitmentTrigger
    -- ^ WP1 (contour closure): 'shouldCommit' fired with this trigger,
    --   but the resulting state remained 'EssenceUncommitted'.
    --   This is a structural inconsistency, not a content mismatch.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Snake_case JSON-schema-stable summary of a violation.
renderEssenceViolation :: EssenceViolation -> Text
renderEssenceViolation = \case
  ViolationFamilyMismatch m f ->
    "family_mismatch:" <> renderEssenceMode m <> ":" <> T.pack (show f)
  ViolationToneMismatch m t ->
    "tone_mismatch:" <> renderEssenceMode m <> ":" <> T.pack (show t)
  ViolationStyleMismatch m s ->
    "style_mismatch:" <> renderEssenceMode m <> ":" <> T.pack (show s)
  ViolationMissingDeliberation m ->
    "missing_deliberation:" <> renderEssenceMode m
  ViolationRefusedCommitment trigger ->
    "refused_commitment:" <> renderCommitmentTrigger trigger

-- | Admissible 'CanonicalMoveFamily' sets per committed mode.
-- 'CMRepair' is admissible in every mode (recovery is orthogonal
-- to essence).
admissibleFamilies :: EssenceMode -> Set CanonicalMoveFamily
admissibleFamilies = \case
  EssenceContemplative ->
    Set.fromList [CMDescribe, CMHypothesis, CMPurpose, CMRepair]
  EssenceDialogical    ->
    Set.fromList [CMContact, CMDeepen, CMRepair, CMReflect]
  EssenceIntegrative   -> Set.fromList [minBound .. maxBound]
  EssenceWitnessing    -> Set.fromList [minBound .. maxBound]

-- | Admissible 'NarrativeTone' sets per committed mode.
-- 'NarrativeNeutral' is admissible in every mode (tonal neutrality
-- is never an essence violation).
admissibleTones :: EssenceMode -> Set NarrativeTone
admissibleTones = \case
  EssenceContemplative ->
    Set.fromList [NarrativeNeutral, NarrativeTerse]
  EssenceDialogical    ->
    Set.fromList [NarrativeNeutral, NarrativeWarm]
  EssenceIntegrative   ->
    Set.fromList [NarrativeNeutral, NarrativeWarm, NarrativeFormal,
                  NarrativeTerse, NarrativeRecovery]
  EssenceWitnessing    ->
    Set.fromList [NarrativeNeutral, NarrativeWarm, NarrativeFormal,
                  NarrativeTerse, NarrativeRecovery]

-- | Admissible 'RenderStyle' sets per committed mode.
-- Contemplative excludes "warm" styles; Dialogical excludes
-- "recovery" styles.  Integrative / Witnessing admit all.
admissibleStyles :: EssenceMode -> Set RenderStyle
admissibleStyles = \case
  EssenceContemplative ->
    Set.fromList [StyleFormal, StyleDirect, StylePoetic,
                  StyleClinical, StyleCautious, StyleRecovery,
                  StyleStandard]
  EssenceDialogical    ->
    Set.fromList [StyleFormal, StyleWarm, StyleDirect, StylePoetic,
                  StyleClinical, StyleCautious, StyleStandard]
  EssenceIntegrative   -> Set.fromList [minBound .. maxBound]
  EssenceWitnessing    -> Set.fromList [minBound .. maxBound]

-- | Validate a reconciled 'Plan' against a committed essence.
-- Priority order: family → tone → style; first mismatch wins.
validatePlan :: EssenceCommitment -> Plan -> Either EssenceViolation Plan
validatePlan c p
  | not (planFamily        p `Set.member` admissibleFamilies (ecMode c))
      = Left (ViolationFamilyMismatch (ecMode c) (planFamily p))
  | not (planNarrativeTone p `Set.member` admissibleTones    (ecMode c))
      = Left (ViolationToneMismatch  (ecMode c) (planNarrativeTone p))
  | not (planRenderStyle   p `Set.member` admissibleStyles   (ecMode c))
      = Left (ViolationStyleMismatch (ecMode c) (planRenderStyle p))
  | otherwise = Right p

-- ---------------------------------------------------------------------------
-- Renderers
-- ---------------------------------------------------------------------------

-- | Snake_case JSON-schema-stable tag for 'EssenceMode'.
-- Stable across builds; any change is a breaking schema change.
renderEssenceMode :: EssenceMode -> Text
renderEssenceMode = \case
  EssenceWitnessing    -> "witnessing"
  EssenceContemplative -> "contemplative"
  EssenceDialogical    -> "dialogical"
  EssenceIntegrative   -> "integrative"

-- | Snake_case JSON-schema-stable tag for 'CommitmentTrigger'.
renderCommitmentTrigger :: CommitmentTrigger -> Text
renderCommitmentTrigger = \case
  TriggerAngstThreshold -> "angst_threshold"
  TriggerConatusErosion -> "conatus_erosion"

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

clampUnit :: Double -> Double
clampUnit = max 0.0 . min 1.0
