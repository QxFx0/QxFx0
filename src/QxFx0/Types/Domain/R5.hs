{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Canonical move-family model and R5 verdict construction. -}
module QxFx0.Types.Domain.R5
  ( CanonicalMoveFamily(..)
  , IllocutionaryForce(..)
  , ClauseForm(..)
  , SemanticLayer(..)
  , WarrantedMoveMode(..)
  , R5Verdict(..)
  , MeaningDirective(..)
  , R5CoreProfile(..)
  , R5PolicyProfile(..)
  , R5EvaluationContext(..)
  , defaultR5CoreProfile
  , defaultR5PolicyProfile
  , mkVerdict
  , mkVerdictWithDirective
  , forceForFamily
  , clauseFormForIF
  , layerForFamily
  , warrantedForFamily
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.=)
  )
import GHC.Generics (Generic)
import Data.Text (Text)

import QxFx0.Self.Field (Field)

data CanonicalMoveFamily
  = CMGround | CMDefine | CMDistinguish | CMReflect | CMDescribe
  | CMPurpose | CMHypothesis | CMRepair | CMContact | CMAnchor
  | CMClarify | CMDeepen | CMConfront | CMNextStep
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON CanonicalMoveFamily where
  toJSON = genericToJSON defaultOptions

instance FromJSON CanonicalMoveFamily where
  parseJSON = genericParseJSON defaultOptions

data IllocutionaryForce
  = IFAsk | IFAssert | IFOffer | IFConfront | IFContact
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON IllocutionaryForce where
  toJSON = genericToJSON defaultOptions

instance FromJSON IllocutionaryForce where
  parseJSON = genericParseJSON defaultOptions

data ClauseForm
  = Declarative | Interrogative | Imperative | Hortative
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON ClauseForm where
  toJSON = genericToJSON defaultOptions

instance FromJSON ClauseForm where
  parseJSON = genericParseJSON defaultOptions

data SemanticLayer
  = ContentLayer | MetaLayer | ContactLayer
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON SemanticLayer where
  toJSON = genericToJSON defaultOptions

instance FromJSON SemanticLayer where
  parseJSON = genericParseJSON defaultOptions

data WarrantedMoveMode
  = AlwaysWarranted | NeverWarranted | ConditionallyWarranted
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON WarrantedMoveMode where
  toJSON = genericToJSON defaultOptions

instance FromJSON WarrantedMoveMode where
  parseJSON = genericParseJSON defaultOptions

data R5Verdict = R5Verdict
  { r5Family :: !CanonicalMoveFamily
  , r5Force :: !IllocutionaryForce
  , r5Clause :: !ClauseForm
  , r5Layer :: !SemanticLayer
  , r5Warranted :: !WarrantedMoveMode
  , r5Directive :: !(Maybe MeaningDirective)
    -- ^ FMAR directive. 'Nothing' on the static (pre-FMAR) path; populated
    -- when FMAR is active. Nullable so legacy construction and legacy JSON
    -- round-trip unchanged.
  } deriving stock (Eq, Ord, Show, Read, Generic)
    deriving anyclass (NFData)

instance ToJSON R5Verdict where
  toJSON r5 =
    object
      [ "family" .= r5Family r5
      , "force" .= r5Force r5
      , "clause" .= r5Clause r5
      , "layer" .= r5Layer r5
      , "warranted" .= r5Warranted r5
      , "directive" .= r5Directive r5
      ]

instance FromJSON R5Verdict where
  parseJSON = withObject "R5Verdict" $ \o ->
    R5Verdict
      <$> o .: "family"
      <*> o .: "force"
      <*> o .: "clause"
      <*> o .: "layer"
      <*> o .: "warranted"
      <*> o .:? "directive"

-- | The FMAR directive attached to an 'R5Verdict'. Defined here (rather than
-- in @QxFx0.Self.MeaningDirective@) to avoid a module import cycle: this type
-- needs the move-family enums above, and 'R5Verdict' needs this type.
-- 'QxFx0.Self.MeaningDirective' re-exports it under the Self-layer name.
data MeaningDirective = MeaningDirective
  { mdFamily            :: !CanonicalMoveFamily
    -- ^ Final family after FMAR + Conatus gate + rescue.
  , mdDetectorFamily    :: !CanonicalMoveFamily
    -- ^ Keyword-detector recommendation (shadow-mode comparison baseline).
  , mdFieldDelta        :: !Field
    -- ^ @targetField(mdFamily) - currentField@; seeds tone-variant selection.
  , mdForce             :: !IllocutionaryForce
  , mdClause            :: !ClauseForm
  , mdLayer             :: !SemanticLayer
  , mdWarranted         :: !WarrantedMoveMode
  , mdConatusGateOk     :: !Bool
    -- ^ Did the Conatus gate permit the FMAR choice (True) or veto it (False)?
  , mdRescueUsed        :: !Bool
    -- ^ Was the Conatus-rescue selection invoked?
  , mdFieldDistance     :: !Double
    -- ^ Distance from current position to the chosen family's target Field.
  , mdAbstractionBudget :: !Int
    -- ^ Repurposed from the former CoreDirective; carried for the renderer.
  , mdMaxWordsHint      :: !Int
    -- ^ Repurposed from the former CoreDirective; carried for the renderer.
  } deriving stock (Eq, Ord, Read, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data R5CoreProfile = R5CoreProfile
  { r5cVersionId :: !Int
  } deriving stock (Eq, Ord, Show, Read, Generic)
    deriving anyclass (NFData)

instance ToJSON R5CoreProfile where
  toJSON = genericToJSON defaultOptions

instance FromJSON R5CoreProfile where
  parseJSON = genericParseJSON defaultOptions

data R5PolicyProfile = R5PolicyProfile
  { r5pVersionId :: !Int
  , r5pStrictnessMode :: !Text
  , r5pShadowBindingMode :: !Text
  , r5pAdvisoryThresholds :: ![(Text, Double)]
  , r5pRecoveryPolicyLink :: !Text
  } deriving stock (Eq, Ord, Show, Read, Generic)
    deriving anyclass (NFData)

instance ToJSON R5PolicyProfile where
  toJSON = genericToJSON defaultOptions

instance FromJSON R5PolicyProfile where
  parseJSON = genericParseJSON defaultOptions

data R5EvaluationContext = R5EvaluationContext
  { r5eCoreVersion :: !Int
  , r5ePolicyVersion :: !Int
  , r5eRuntimeMode :: !Text
  , r5eScope :: !(Maybe Text)
  } deriving stock (Eq, Ord, Show, Read, Generic)
    deriving anyclass (NFData)

instance ToJSON R5EvaluationContext where
  toJSON = genericToJSON defaultOptions

instance FromJSON R5EvaluationContext where
  parseJSON = genericParseJSON defaultOptions

defaultR5CoreProfile :: R5CoreProfile
defaultR5CoreProfile = R5CoreProfile
  { r5cVersionId = 1
  }

defaultR5PolicyProfile :: R5PolicyProfile
defaultR5PolicyProfile = R5PolicyProfile
  { r5pVersionId = 1
  , r5pStrictnessMode = "binding_in_strict_only"
  , r5pShadowBindingMode = "binding_in_strict_only"
  , r5pAdvisoryThresholds = [("shadow_advisory", 1.0)]
  , r5pRecoveryPolicyLink = "local_recovery_policy"
  }

forceForFamily :: CanonicalMoveFamily -> IllocutionaryForce
forceForFamily CMGround = IFAssert
forceForFamily CMDefine = IFAssert
forceForFamily CMDistinguish = IFAssert
forceForFamily CMReflect = IFAssert
forceForFamily CMDescribe = IFAssert
forceForFamily CMPurpose = IFAssert
forceForFamily CMHypothesis = IFAsk
forceForFamily CMRepair = IFOffer
forceForFamily CMContact = IFContact
forceForFamily CMAnchor = IFAssert
forceForFamily CMClarify = IFAsk
forceForFamily CMDeepen = IFAsk
forceForFamily CMConfront = IFConfront
forceForFamily CMNextStep = IFOffer

clauseFormForIF :: IllocutionaryForce -> ClauseForm
clauseFormForIF IFAsk = Interrogative
clauseFormForIF IFAssert = Declarative
clauseFormForIF IFOffer = Hortative
clauseFormForIF IFConfront = Imperative
clauseFormForIF IFContact = Declarative

layerForFamily :: CanonicalMoveFamily -> SemanticLayer
layerForFamily CMGround = ContentLayer
layerForFamily CMDefine = ContentLayer
layerForFamily CMDistinguish = ContentLayer
layerForFamily CMReflect = MetaLayer
layerForFamily CMDescribe = ContentLayer
layerForFamily CMPurpose = ContentLayer
layerForFamily CMHypothesis = MetaLayer
layerForFamily CMRepair = MetaLayer
layerForFamily CMContact = ContactLayer
layerForFamily CMAnchor = ContentLayer
layerForFamily CMClarify = MetaLayer
layerForFamily CMDeepen = MetaLayer
layerForFamily CMConfront = MetaLayer
layerForFamily CMNextStep = MetaLayer

warrantedForFamily :: CanonicalMoveFamily -> WarrantedMoveMode
warrantedForFamily CMGround = AlwaysWarranted
warrantedForFamily CMDefine = AlwaysWarranted
warrantedForFamily CMDistinguish = ConditionallyWarranted
warrantedForFamily CMReflect = AlwaysWarranted
warrantedForFamily CMDescribe = AlwaysWarranted
warrantedForFamily CMPurpose = ConditionallyWarranted
warrantedForFamily CMHypothesis = ConditionallyWarranted
warrantedForFamily CMRepair = AlwaysWarranted
warrantedForFamily CMContact = AlwaysWarranted
warrantedForFamily CMAnchor = AlwaysWarranted
warrantedForFamily CMClarify = ConditionallyWarranted
warrantedForFamily CMDeepen = ConditionallyWarranted
warrantedForFamily CMConfront = NeverWarranted
warrantedForFamily CMNextStep = ConditionallyWarranted

mkVerdict :: CanonicalMoveFamily -> R5Verdict
mkVerdict fam =
  R5Verdict
    { r5Family = fam
    , r5Force = forceForFamily fam
    , r5Clause = clauseFormForIF (forceForFamily fam)
    , r5Layer = layerForFamily fam
    , r5Warranted = warrantedForFamily fam
    , r5Directive = Nothing
    }

-- | Build a verdict carrying an FMAR 'MeaningDirective'. The verdict's
-- surface fields are derived from the directive's final family, so the
-- verdict stays internally consistent with the FMAR decision.
mkVerdictWithDirective :: MeaningDirective -> R5Verdict
mkVerdictWithDirective directive =
  let fam = mdFamily directive
   in R5Verdict
        { r5Family = fam
        , r5Force = forceForFamily fam
        , r5Clause = clauseFormForIF (forceForFamily fam)
        , r5Layer = layerForFamily fam
        , r5Warranted = warrantedForFamily fam
        , r5Directive = Just directive
        }
