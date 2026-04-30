{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Atom- and scene-level domain types shared across parsing, runtime traces, and rendering. -}
module QxFx0.Types.Domain.Atoms
  ( Embedding
  , AtomTag(..)
  , MeaningAtom(..)
  , AtomSet(..)
  , AtomTrace(..)
  , emptyAtomTrace
  , Register(..)
  , SemanticScene(..)
  , NixGuardStatus(..)
  , SourceTier(..)
  , LexemeCase(..)
  , LexemeNumber(..)
  , LexemeForm(..)
  , MorphologyData(..)
  ) where

import Control.DeepSeq (NFData)
import Control.Applicative ((<|>))
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  , object
  , withArray
  , withObject
  , (.!=)
  , (.:)
  , (.:?)
  , (.=)
  )
import qualified Data.Vector as V
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)
import GHC.Generics (Generic)
import QxFx0.Types.Thresholds (atomTraceAlphaDefault)

type Embedding = Vector Float

data AtomTag
  = Searching !Text
  | Exhaustion !Text
  | Verification !Text
  | Doubt !Text
  | NeedContact !Text
  | NeedMeaning !Text
  | AgencyLost !Double
  | AgencyFound !Double
  | Anchoring !Text
  | Contradiction !Text !Text
  | CustomAtom !Text !Text
  | AffectiveAtom !Text !Double
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData)

instance ToJSON AtomTag where
  toJSON (Searching t) = object ["tag" .= ("Searching" :: Text), "payload" .= t]
  toJSON (Exhaustion t) = object ["tag" .= ("Exhaustion" :: Text), "payload" .= t]
  toJSON (Verification t) = object ["tag" .= ("Verification" :: Text), "payload" .= t]
  toJSON (Doubt t) = object ["tag" .= ("Doubt" :: Text), "payload" .= t]
  toJSON (NeedContact t) = object ["tag" .= ("NeedContact" :: Text), "payload" .= t]
  toJSON (NeedMeaning t) = object ["tag" .= ("NeedMeaning" :: Text), "payload" .= t]
  toJSON (AgencyLost d) = object ["tag" .= ("AgencyLost" :: Text), "payload" .= d]
  toJSON (AgencyFound d) = object ["tag" .= ("AgencyFound" :: Text), "payload" .= d]
  toJSON (Anchoring t) = object ["tag" .= ("Anchoring" :: Text), "payload" .= t]
  toJSON (Contradiction a b) = object ["tag" .= ("Contradiction" :: Text), "left" .= a, "right" .= b]
  toJSON (CustomAtom t v) = object ["tag" .= ("CustomAtom" :: Text), "label" .= t, "payload" .= v]
  toJSON (AffectiveAtom t d) = object ["tag" .= ("AffectiveAtom" :: Text), "label" .= t, "valence" .= d]

instance FromJSON AtomTag where
  parseJSON = withObject "AtomTag" $ \o -> do
    tag <- o .: "tag"
    case tag :: Text of
      "Searching" -> Searching <$> o .: "payload"
      "Exhaustion" -> Exhaustion <$> o .: "payload"
      "Verification" -> Verification <$> o .: "payload"
      "Doubt" -> Doubt <$> o .: "payload"
      "NeedContact" -> NeedContact <$> o .: "payload"
      "NeedMeaning" -> NeedMeaning <$> o .: "payload"
      "AgencyLost" -> AgencyLost <$> o .: "payload"
      "AgencyFound" -> AgencyFound <$> o .: "payload"
      "Anchoring" -> Anchoring <$> o .: "payload"
      "Contradiction" -> Contradiction <$> o .: "left" <*> o .: "right"
      "CustomAtom" -> CustomAtom <$> o .: "label" <*> o .: "payload"
      "AffectiveAtom" -> AffectiveAtom <$> o .: "label" <*> o .: "valence"
      _ -> fail $ "unknown AtomTag: " ++ T.unpack tag

data MeaningAtom = MeaningAtom
  { maText :: !Text
  , maTag :: !AtomTag
  , maEmbedding :: !Embedding
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON MeaningAtom where
  toJSON = genericToJSON defaultOptions

instance FromJSON MeaningAtom where
  parseJSON = genericParseJSON defaultOptions

data AtomSet = AtomSet
  { asAtoms :: ![MeaningAtom]
  , asLoad :: !Double
  , asRegister :: !Register
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON AtomSet where
  toJSON = genericToJSON defaultOptions

instance FromJSON AtomSet where
  parseJSON = genericParseJSON defaultOptions

data AtomTrace = AtomTrace
  { atAlpha :: !Double
  , atHistory :: ![(Int, Double)]
  , atCurrentLoad :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON AtomTrace where
  toJSON = genericToJSON defaultOptions

instance FromJSON AtomTrace where
  parseJSON = genericParseJSON defaultOptions

emptyAtomTrace :: AtomTrace
emptyAtomTrace = AtomTrace atomTraceAlphaDefault [] 0.0

data Register
  = Exhaust | Contact | Search | Anchor | Verify | Neutral
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON Register where
  toJSON = genericToJSON defaultOptions

instance FromJSON Register where
  parseJSON = genericParseJSON defaultOptions

data SemanticScene = SemanticScene
  { sceLoadMin :: !Double
  , sceLoadMax :: !Double
  , sceTags :: ![AtomTag]
  , sceDescription :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SemanticScene where
  toJSON = genericToJSON defaultOptions

instance FromJSON SemanticScene where
  parseJSON = genericParseJSON defaultOptions

data NixGuardStatus
  = Allowed
  | Blocked !Text
  | Unavailable !Text
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData)

instance ToJSON NixGuardStatus where
  toJSON Allowed = object ["tag" .= ("Allowed" :: Text)]
  toJSON (Blocked t) = object ["tag" .= ("Blocked" :: Text), "reason" .= t]
  toJSON (Unavailable t) = object ["tag" .= ("Unavailable" :: Text), "reason" .= t]

instance FromJSON NixGuardStatus where
  parseJSON = withObject "NixGuardStatus" $ \o -> do
    tag <- o .: "tag"
    case tag :: Text of
      "Allowed" -> pure Allowed
      "Blocked" -> Blocked <$> o .: "reason"
      "Unavailable" -> Unavailable <$> o .: "reason"
      _ -> fail $ "unknown NixGuardStatus: " ++ T.unpack tag

data SourceTier
  = CuratedTier
  | BrainKbReviewedTier
  | AutoVerifiedTier
  | AutoCoverageTier
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
    deriving anyclass (NFData)

instance ToJSON SourceTier where
  toJSON CuratedTier       = "curated"
  toJSON BrainKbReviewedTier = "brain-kb-reviewed"
  toJSON AutoVerifiedTier  = "auto-verified"
  toJSON AutoCoverageTier  = "auto-coverage"

instance FromJSON SourceTier where
  parseJSON "curated"       = pure CuratedTier
  parseJSON "brain-kb-reviewed" = pure BrainKbReviewedTier
  parseJSON "auto-verified" = pure AutoVerifiedTier
  parseJSON "auto-coverage" = pure AutoCoverageTier
  parseJSON _               = fail ("unknown SourceTier")

data LexemeCase
  = NominativeCase
  | GenitiveCase
  | DativeCase
  | AccusativeCase
  | InstrumentalCase
  | PrepositionalCase
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
    deriving anyclass (NFData)

instance ToJSON LexemeCase where
  toJSON NominativeCase    = "nominative"
  toJSON GenitiveCase      = "genitive"
  toJSON DativeCase        = "dative"
  toJSON AccusativeCase    = "accusative"
  toJSON InstrumentalCase  = "instrumental"
  toJSON PrepositionalCase = "prepositional"

instance FromJSON LexemeCase where
  parseJSON "nominative"    = pure NominativeCase
  parseJSON "genitive"      = pure GenitiveCase
  parseJSON "dative"        = pure DativeCase
  parseJSON "accusative"    = pure AccusativeCase
  parseJSON "instrumental"  = pure InstrumentalCase
  parseJSON "prepositional" = pure PrepositionalCase
  parseJSON _               = fail ("unknown LexemeCase")

data LexemeNumber
  = SingularNumber
  | PluralNumber
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
    deriving anyclass (NFData)

instance ToJSON LexemeNumber where
  toJSON SingularNumber = "singular"
  toJSON PluralNumber   = "plural"

instance FromJSON LexemeNumber where
  parseJSON "singular" = pure SingularNumber
  parseJSON "plural"   = pure PluralNumber
  parseJSON _          = fail ("unknown LexemeNumber")

data LexemeForm = LexemeForm
  { lfSurface :: !Text
  , lfLemma :: !Text
  , lfPOS :: !Text
  , lfCase :: !LexemeCase
  , lfNumber :: !LexemeNumber
  , lfTier :: !SourceTier
  , lfQuality :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON LexemeForm where
  toJSON (LexemeForm s l p c n t q) = object
    [ "surface"  .= s
    , "lemma"    .= l
    , "pos"      .= p
    , "case"     .= c
    , "number"   .= n
    , "tier"     .= t
    , "quality"  .= q
    ]

instance FromJSON LexemeForm where
  parseJSON v = parseObject v <|> parseArray v
    where
      parseObject = withObject "LexemeForm" $ \o -> LexemeForm
        <$> o .: "surface"
        <*> o .: "lemma"
        <*> o .: "pos"
        <*> o .: "case"
        <*> o .: "number"
        <*> o .: "tier"
        <*> o .: "quality"
      parseArray = withArray "LexemeForm" $ \arr -> do
        let a = V.toList arr
        case a of
          [s, l, p, c, n, t, q] -> LexemeForm
            <$> parseJSON s
            <*> parseJSON l
            <*> parseJSON p
            <*> parseJSON c
            <*> parseJSON n
            <*> parseJSON t
            <*> parseJSON q
          _ -> fail $ "Parser: LexemeForm compact array must have exactly 7 elements: [surface, lemma, pos, case, number, tier, quality]"

data MorphologyData = MorphologyData
  { mdPrepositional :: !(Map Text Text)
  , mdGenitive :: !(Map Text Text)
  , mdNominative :: !(Map Text Text)
  , mdFormsBySurface :: !(Map Text [LexemeForm])
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON MorphologyData where
  toJSON = genericToJSON defaultOptions

instance FromJSON MorphologyData where
  parseJSON = withObject "MorphologyData" $ \o -> MorphologyData
    <$> o .: "mdPrepositional"
    <*> o .: "mdGenitive"
    <*> o .: "mdNominative"
    <*> o .:? "mdFormsBySurface" .!= M.empty
