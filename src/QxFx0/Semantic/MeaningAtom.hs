{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-|
MeaningAtom: atomic semantic slots for structured knowledge decomposition.

Each fact from the knowledge base is decomposed into a set of tagged MeaningAtom
slots. Assembly operations (defineStep, quantifyStep, etc.) consume these slots
and produce text — NOT by selecting a pre-written template, but by
functionally combining slot values with morphological forms and style-dependent
phrasing.
-}
module QxFx0.Semantic.MeaningAtom
  ( MeaningAtom(..)
  , AtomSlot(..)
  , FactAtoms(..)
  , emptyFactAtoms
  , slotValue
  , hasAtom
  , plainSlot
  , nounSlot
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), FromJSONKey(..), FromJSONKeyFunction(..), ToJSON(..), ToJSONKey(..), ToJSONKeyFunction(..), toJSON, toEncoding)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Text.Read (readMaybe)

--------------------------------------------------------------------------------
-- Atom slot types
--------------------------------------------------------------------------------

{-| Semantic slot kind — what role does this piece of information play? -}
data MeaningAtom
  = AtomSubject      -- ^ The entity being discussed (сердце, кровь, Солнце)
  | AtomPredicate    -- ^ Action or property (сокращается, течёт, излучает)
  | AtomQuantity     -- ^ Numeric value (100 000, 7 000, 2,5)
  | AtomUnit         -- ^ Unit of measurement (сокращений, литров, км/с)
  | AtomPeriod       -- ^ Time frame (в сутки, за секунду, миллионы лет)
  | AtomEffect       -- ^ Result/consequence (перекачивает кровь, освещает Землю)
  | AtomMechanism    -- ^ How it works (мышечное сокращение, ядерный синтез)
  | AtomContext      -- ^ Broader system (кровеносная система, Солнечная система)
  | AtomRelation     -- ^ Connection to other concepts (part_of, regulates, orbits)
  | AtomScale        -- ^ Comparison reference (35 полных ванн, как теннисный мяч)
  | AtomLocation     -- ^ Where (в грудной клетке, в центре Солнечной системы)
  | AtomProperty     -- ^ Attribute (полый, мышечный, красный, горячий)
  | AtomDiscoverer   -- ^ Who discovered/first described
  | AtomYear         -- ^ Historical moment (1901, XIV век)
   | AtomReason       -- ^ Causal explanation (почему это важно)
   | AtomCondition    -- ^ Under what conditions
   | AtomAnalogy      -- ^ Pre-computed analogy (работает как насос)
    | TVerb           -- ^ Verb/action in a fact: "распределяет", "сокращается"
    | TObject         -- ^ Object of action: "кровь", "органы", "кислород"
    | TCondition      -- ^ Condition/prerequisite: "без учёта", "при отсутствии"
    | TVerbReason     -- ^ Verb in a reason clause: "доставлять", "требовать"
    | TObjectReason   -- ^ Object of the reason verb: "кислород", "совместимость"
   | TModifier       -- ^ Adjectival modifier: "крупнейший", "красный", "насыщенный"
   | TQuantity       -- ^ Numeric quantity extracted from scale: "2,5", "1869"
   | TRelation       -- ^ Relation from decomposed scale: "длиннее экватора Земли"
    deriving stock (Eq, Ord, Show, Generic, Bounded, Enum, Read)
   deriving anyclass (NFData, ToJSON, FromJSON)

instance ToJSONKey MeaningAtom where
  toJSONKey = ToJSONKeyValue toJSON toEncoding
instance FromJSONKey MeaningAtom where
  fromJSONKey = FromJSONKeyTextParser $ \t ->
    case readMaybe (T.unpack t) of
      Just tag -> pure tag
      Nothing  -> fail ("Unknown MeaningAtom: " ++ T.unpack t)

--------------------------------------------------------------------------------
-- Concrete slot value
--------------------------------------------------------------------------------

{-| One slot: an atom kind plus its concrete text value.
  Additional case forms are stored for morphological variation. -}
data AtomSlot = AtomSlot
  { asAtom :: !MeaningAtom
  , asValue :: !Text              -- ^ Primary form (usually nominative)
  , asGen :: !Text                -- ^ Genitive form
  , asPrep :: !Text               -- ^ Prepositional form
  , asAcc :: !Text                -- ^ Accusative form
  , asIns :: !Text                -- ^ Instrumental form
  , asPlural :: !Text             -- ^ Plural nominative
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

{-| Simple slot with no case variants (for numbers, units, etc.) -}
plainSlot :: MeaningAtom -> Text -> AtomSlot
plainSlot atom val = AtomSlot atom val val val val val val

{-| Slot with a noun/lemma and its full 5-case forms. -}
nounSlot :: MeaningAtom -> Text -> Text -> Text -> Text -> Text -> Text -> AtomSlot
nounSlot atom nom gen prep acc ins pl =
  AtomSlot atom nom gen prep acc ins pl

--------------------------------------------------------------------------------
-- FactAtoms: a decomposed fact
--------------------------------------------------------------------------------

{-| One decomposed fact = a set of AtomSlots keyed by MeaningAtom.
  Multiple slots of the same kind are possible (e.g. several properties). -}
newtype FactAtoms = FactAtoms
  { faSlots :: Map MeaningAtom [AtomSlot]
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

emptyFactAtoms :: FactAtoms
emptyFactAtoms = FactAtoms M.empty

slotValue :: MeaningAtom -> FactAtoms -> [AtomSlot]
slotValue atom (FactAtoms m) = M.findWithDefault [] atom m

hasAtom :: MeaningAtom -> FactAtoms -> Bool
hasAtom atom = not . null . slotValue atom