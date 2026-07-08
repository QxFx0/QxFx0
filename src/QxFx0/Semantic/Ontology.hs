{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE DerivingStrategies   #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE StrictData           #-}

{-|
Module      : QxFx0.Semantic.Ontology
Description : Phase I typed ontology graph loaded from the canonical JSONL file.

This module provides a read-only, in-memory concept hierarchy.  Each line of
@resources/knowledge/ontology.jsonl@ becomes an 'OntologyNode'; parent
references are resolved in a second pass to populate child sets and the root
set.
-}
module QxFx0.Semantic.Ontology
  ( ConceptCategory(..)
  , OntologyNode(..)
  , Ontology(..)
  , loadOntology
  , lookupOntologyNode
  , lookupCategory
  , lookupParent
  , lookupSiblings
  , lookupChildren
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(parseJSON), eitherDecodeStrict, withObject, (.:))
import Data.Foldable (foldl')
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)

import QxFx0.Semantic.Content (ConceptCategory(..))

-- | A single concept in the ontology hierarchy.
data OntologyNode = OntologyNode
  { onName     :: !Text
  , onCategory :: !ConceptCategory
  , onParent   :: !(Maybe Text)
  , onChildren :: !(Set Text)
  , onDepth    :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | In-memory ontology graph.
data Ontology = Ontology
  { otNodes :: !(Map Text OntologyNode)
  , otRoots :: !(Set Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | Intermediate representation used only while loading the JSONL file.
data RawNode = RawNode
  { rawName     :: !Text
  , rawCategory :: !ConceptCategory
  , rawParent   :: !(Maybe Text)
  , rawDepth    :: !Int
  }

-- | Convert the category strings used in the JSONL file into the typed
-- 'ConceptCategory' from 'QxFx0.Semantic.Content'.
parseConceptCategory :: Text -> Maybe ConceptCategory
parseConceptCategory t =
  case T.strip t of
    "Philosophical" -> Just CategoryPhilosophical
    "Social"        -> Just CategorySocial
    "Psychological" -> Just CategoryPsychological
    "Physical"      -> Just CategoryPhysical
    "General"       -> Just CategoryGeneral
    _               -> Nothing

instance FromJSON RawNode where
  parseJSON = withObject "OntologyNode" $ \o -> do
    name     <- o .: "name"
    catText  <- o .: "category"
    parent   <- o .: "parent"
    depth    <- o .: "depth"
    category <- case parseConceptCategory catText of
                  Just c  -> pure c
                  Nothing -> fail ("Unknown category for " ++ T.unpack name ++ ": " ++ T.unpack catText)
    let parent' = if T.null parent then Nothing else Just parent
    pure RawNode
      { rawName     = name
      , rawCategory = category
      , rawParent   = parent'
      , rawDepth    = depth
      }

-- | Load an ontology from a JSONL file.
--
-- Each line must contain the fields @name@, @category@, @parent@, and @depth@.
-- Root nodes have an empty @parent@.  The loader builds the child sets and
-- root set from these parent references.
loadOntology :: FilePath -> IO Ontology
loadOntology path = do
  contents <- BS.readFile path
  let rawLines = T.lines (TE.decodeUtf8 contents)
  rawNodes <- traverse parseLine rawLines
  let byName     = foldl' insertRaw Map.empty rawNodes
      withChildren = foldl' attachChild byName rawNodes
      roots = Set.fromList [ onName n | n <- Map.elems withChildren, Nothing == onParent n ]
  pure Ontology
    { otNodes = withChildren
    , otRoots = roots
    }
  where
    parseLine :: Text -> IO RawNode
    parseLine line
      | T.null (T.strip line) = fail "Empty ontology line"
      | otherwise =
          case eitherDecodeStrict (TE.encodeUtf8 line) of
            Left err  -> fail ("Failed to parse ontology line: " ++ err)
            Right raw -> pure raw

    insertRaw :: Map Text OntologyNode -> RawNode -> Map Text OntologyNode
    insertRaw acc RawNode{rawName = name, rawCategory = category, rawParent = parent, rawDepth = depth} =
      let node = OntologyNode
            { onName     = name
            , onCategory = category
            , onParent   = parent
            , onChildren = Set.empty
            , onDepth    = depth
            }
      in Map.insert name node acc

    attachChild :: Map Text OntologyNode -> RawNode -> Map Text OntologyNode
    attachChild acc RawNode{rawName = child, rawParent = Nothing}   = acc
    attachChild acc RawNode{rawName = child, rawParent = Just parent} =
      Map.adjust (\n -> n { onChildren = Set.insert child (onChildren n) }) parent acc

-- | Lookup a node by concept name.
lookupOntologyNode :: Ontology -> Text -> Maybe OntologyNode
lookupOntologyNode ot name = Map.lookup name (otNodes ot)

-- | Lookup the category of a concept.
lookupCategory :: Ontology -> Text -> Maybe ConceptCategory
lookupCategory ot name = onCategory <$> Map.lookup name (otNodes ot)

-- | Lookup the parent of a concept.
lookupParent :: Ontology -> Text -> Maybe Text
lookupParent ot name = Map.lookup name (otNodes ot) >>= onParent

-- | Lookup the siblings of a concept (other nodes sharing the same parent).
-- The result is sorted alphabetically and excludes the queried concept.
lookupSiblings :: Ontology -> Text -> [Text]
lookupSiblings ot name =
  case Map.lookup name (otNodes ot) >>= onParent of
    Nothing  -> []
    Just par ->
      sort [ onName n
           | n <- Map.elems (otNodes ot)
           , onParent n == Just par
           , onName n /= name
           ]

-- | Lookup the direct children of a concept.
-- The result is sorted alphabetically.
lookupChildren :: Ontology -> Text -> [Text]
lookupChildren ot name =
  case Map.lookup name (otNodes ot) of
    Nothing   -> []
    Just node -> sort (Set.toList (onChildren node))
