{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  , ShadowDivergenceSeverity(..)
  , shadowDivergenceKindText
  , shadowDivergenceSeverityText
  , ShadowSnapshot(..)
  , ShadowSnapshotId(..)
  , shadowSnapshotIdText
  , mkShadowSnapshotId
  , emptyShadowDivergence
  , computeShadowLegitimacyPenalty
  , computeShadowLegitimacyPenaltyWithSeverity
  ) where

import Data.Bits (xor)
import Data.Char (ord)
import Data.Aeson (ToJSON(..))
import Data.Text (Text)
import qualified Data.Text as T
import Numeric (showHex)
import Data.Word (Word64)
import QxFx0.Types.Domain
  ( AtomTag
  , CanonicalMoveFamily
  , IllocutionaryForce
  )
import QxFx0.Types.Thresholds.Legitimacy
  ( shadowPenaltyClauseMismatch
  , shadowPenaltyFamilyMismatch
  , shadowPenaltyForceMismatch
  , shadowPenaltyLayerMismatch
  , shadowPenaltyWarrantedMismatch
  )

data ShadowDivergenceKind
  = ShadowNoDivergence
  | ShadowVerdictMismatch
  | ShadowUnavailableDivergence
  | ShadowBridgeSkew
  | ShadowExecutionError
  deriving stock (Eq, Show, Read)

instance ToJSON ShadowDivergenceKind where
  toJSON = toJSON . shadowDivergenceKindText

data ShadowDivergenceSeverity
  = ShadowSeverityClean
  | ShadowSeverityAdvisory
  | ShadowSeveritySafety
  | ShadowSeverityContract
  | ShadowSeverityUnavailable
  deriving stock (Eq, Show, Read)

instance ToJSON ShadowDivergenceSeverity where
  toJSON = toJSON . shadowDivergenceSeverityText

shadowDivergenceKindText :: ShadowDivergenceKind -> Text
shadowDivergenceKindText ShadowNoDivergence = "none"
shadowDivergenceKindText ShadowVerdictMismatch = "verdict_mismatch"
shadowDivergenceKindText ShadowUnavailableDivergence = "shadow_unavailable"
shadowDivergenceKindText ShadowBridgeSkew = "bridge_skew"
shadowDivergenceKindText ShadowExecutionError = "execution_error"

shadowDivergenceSeverityText :: ShadowDivergenceSeverity -> Text
shadowDivergenceSeverityText ShadowSeverityClean = "clean"
shadowDivergenceSeverityText ShadowSeverityAdvisory = "advisory"
shadowDivergenceSeverityText ShadowSeveritySafety = "safety"
shadowDivergenceSeverityText ShadowSeverityContract = "contract"
shadowDivergenceSeverityText ShadowSeverityUnavailable = "unavailable"

data ShadowSnapshot = ShadowSnapshot
  { ssRequestedFamily :: !CanonicalMoveFamily
  , ssInputForce :: !IllocutionaryForce
  , ssInputAtoms :: ![Text]
  , ssInputAtomDetails :: ![(Text, Text)]
  , ssSourceAtomTags :: ![AtomTag]
  } deriving stock (Eq, Show)

newtype ShadowSnapshotId = ShadowSnapshotId { unShadowSnapshotId :: Text }
  deriving stock (Eq, Show, Read)

instance ToJSON ShadowSnapshotId where
  toJSON = toJSON . unShadowSnapshotId

shadowSnapshotIdText :: ShadowSnapshotId -> Text
shadowSnapshotIdText = unShadowSnapshotId

mkShadowSnapshotId :: ShadowSnapshot -> ShadowSnapshotId
mkShadowSnapshotId snapshot =
  let payload =
        T.intercalate
          "|"
          [ T.pack (show (ssRequestedFamily snapshot))
          , T.pack (show (ssInputForce snapshot))
          , T.intercalate "," (ssInputAtoms snapshot)
          , T.intercalate "," (map (\(k, v) -> k <> "=" <> v) (ssInputAtomDetails snapshot))
          ]
      hashValue = fnv1a64 payload
      asHex = T.pack (padHex16 (showHex hashValue ""))
  in ShadowSnapshotId ("shadow:" <> asHex)

fnv1a64 :: Text -> Word64
fnv1a64 =
  T.foldl'
    (\acc ch -> (acc `xor` fromIntegral (ord ch)) * 1099511628211)
    1469598103934665603

padHex16 :: String -> String
padHex16 raw =
  let n = length raw
  in replicate (max 0 (16 - n)) '0' <> raw

data ShadowDivergence = ShadowDivergence
  { sdKind :: !ShadowDivergenceKind
  , sdFamilyMismatch :: !Bool
  , sdForceMismatch :: !Bool
  , sdClauseMismatch :: !Bool
  , sdLayerMismatch :: !Bool
  , sdWarrantedMismatch :: !Bool
  } deriving stock (Eq, Show)

emptyShadowDivergence :: ShadowDivergence
emptyShadowDivergence = ShadowDivergence
  { sdKind = ShadowNoDivergence
  , sdFamilyMismatch = False
  , sdForceMismatch = False
  , sdClauseMismatch = False
  , sdLayerMismatch = False
  , sdWarrantedMismatch = False
  }

computeShadowLegitimacyPenalty :: ShadowDivergence -> Double
computeShadowLegitimacyPenalty divergence =
  let penalty = 0.0
      penalty' = if sdFamilyMismatch divergence then penalty + shadowPenaltyFamilyMismatch else penalty
      penalty'' = if sdForceMismatch divergence then penalty' + shadowPenaltyForceMismatch else penalty'
      penalty''' = if sdClauseMismatch divergence then penalty'' + shadowPenaltyClauseMismatch else penalty''
      penalty'''' = if sdLayerMismatch divergence then penalty''' + shadowPenaltyLayerMismatch else penalty'''
      penalty''''' = if sdWarrantedMismatch divergence then penalty'''' + shadowPenaltyWarrantedMismatch else penalty''''
  in min 1.0 penalty'''''

computeShadowLegitimacyPenaltyWithSeverity :: ShadowDivergenceSeverity -> ShadowDivergence -> Double
computeShadowLegitimacyPenaltyWithSeverity severity divergence =
  case severity of
    ShadowSeverityClean -> 0.0
    ShadowSeverityAdvisory -> 0.0
    ShadowSeveritySafety -> computeShadowLegitimacyPenalty divergence
    ShadowSeverityContract -> computeShadowLegitimacyPenalty divergence
    ShadowSeverityUnavailable -> computeShadowLegitimacyPenalty divergence
