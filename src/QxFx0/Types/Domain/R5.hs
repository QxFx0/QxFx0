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
  , mkVerdict
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
  , (.=)
  )
import GHC.Generics (Generic)

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
      ]

instance FromJSON R5Verdict where
  parseJSON = withObject "R5Verdict" $ \o ->
    R5Verdict
      <$> o .: "family"
      <*> o .: "force"
      <*> o .: "clause"
      <*> o .: "layer"
      <*> o .: "warranted"

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
    }
