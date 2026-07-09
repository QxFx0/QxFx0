{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE StrictData         #-}

{-|
Module      : QxFx0.Semantic.Network.Ingest
Description : ADR-0052 Phase I — ingest external knowledge files into a
              'SemanticNetwork' and seed graph structures.

This module loads the external relation corpus
(@resources/knowledge/relations.jsonl@) and the typed ontology
(@resources/knowledge/ontology.jsonl@) and turns them into the
project's existing graph types: 'Relation'/'AtomGraph' and
'SemanticNetwork'.
-}
module QxFx0.Semantic.Network.Ingest
  ( LoadedRelation(..)
  , loadRelations
  , loadRelationGraph
  , ingestExternalKnowledge
  , buildNetworkFromAtomGraph
  , semanticNetworkFromLoaded
  , loadSelfPlayRelations
  , mergeSelfPlayRelations
  , normalizeRelationText
  ) where

import Control.Applicative ((<|>))
import Control.DeepSeq (NFData)
import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON(parseJSON), ToJSON(toJSON), eitherDecodeStrict, object, withObject, (.:), (.:?), (.=))
import Data.Foldable (foldl')
import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import GHC.Generics (Generic)
import System.IO (hPutStrLn, stderr)

import QxFx0.Semantic.Content.AtomStore
  ( Atom(..)
  , AtomGraph(..)
  , AtomId(..)
  , ObjectCase(..)
  , Relation(..)
  , RelationSource(..)
  , RelationType(..)
  , atomStore
  )
import QxFx0.Semantic.Morphology (toNominative)
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import QxFx0.Semantic.Network
  ( mergeSemanticNetworks
  )
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , relationTypeWeight
  )
import qualified QxFx0.Semantic.Network.Types as NetTypes
import QxFx0.Semantic.Ontology (Ontology(..), OntologyNode(..), loadOntology)

-- ============================================================
-- LoadedRelation
-- ============================================================

-- | External relation record matching the JSONL schema used by
-- @resources/knowledge/relations.jsonl@.
data LoadedRelation = LoadedRelation
  { lrFrom :: !Text
  , lrTo :: !Text
  , lrType :: !RelationType
  , lrVerb :: !(Maybe Text)
  , lrRationale :: !(Maybe Text)
  , lrCounter :: !(Maybe Text)
  , lrSynthesis :: !(Maybe Text)
  , lrConfidence :: !Double
  , lrAuthor :: !Text
  , lrVersion :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | Parse a 'RelationType' from its constructor name as it appears
-- in the JSONL file (e.g. @\"RelPresupposes\"@).
parseRelationType :: Text -> Maybe RelationType
parseRelationType t = case T.strip t of
  "RelPresupposes"    -> Just RelPresupposes
  "RelLimitedBy"      -> Just RelLimitedBy
  "RelRequires"       -> Just RelRequires
  "RelClaims"         -> Just RelClaims
  "RelVerifiedBy"     -> Just RelVerifiedBy
  "RelSignals"        -> Just RelSignals
  "RelTransformsInto" -> Just RelTransformsInto
  "RelExpresses"      -> Just RelExpresses
  "RelDiffersFrom"    -> Just RelDiffersFrom
  "RelRelatedTo"      -> Just RelRelatedTo
  "RelDirectedAt"     -> Just RelDirectedAt
  "RelPreserves"      -> Just RelPreserves
  "RelOrientsToward"  -> Just RelOrientsToward
  "RelPrescribes"     -> Just RelPrescribes
  "RelBuiltThrough"   -> Just RelBuiltThrough
  "RelDenotes"        -> Just RelDenotes
  "RelStructures"     -> Just RelStructures
  "RelDetermines"     -> Just RelDetermines
  "RelTransforms"     -> Just RelTransforms
  "RelGives"          -> Just RelGives
  "RelReveals"        -> Just RelReveals
  "RelRecognizes"     -> Just RelRecognizes
  "RelUnifies"        -> Just RelUnifies
  "RelConnects"       -> Just RelConnects
  "RelPrecedes"       -> Just RelPrecedes
  "RelDependsOn"      -> Just RelDependsOn
  "RelIncludes"       -> Just RelIncludes
  "RelNecessaryFor"   -> Just RelNecessaryFor
  "RelEvokes"         -> Just RelEvokes
  "RelMeans"          -> Just RelMeans
  "RelSays"           -> Just RelSays
  "RelNegates"        -> Just RelNegates
  "RelContrastsWith"  -> Just RelContrastsWith
  "RelNotReducibleTo" -> Just RelNotReducibleTo
  "RelIsNot"          -> Just RelIsNot
  "RelCapableOf"      -> Just RelCapableOf
  "RelCreatedFrom"    -> Just RelCreatedFrom
  "RelReliesOn"       -> Just RelReliesOn
  "RelCanBe"          -> Just RelCanBe
  "RelDestroys"       -> Just RelDestroys
  "RelPointsTo"       -> Just RelPointsTo
  "RelMakes"          -> Just RelMakes
  "RelIsA"            -> Just RelIsA
  "RelReconstructs"   -> Just RelReconstructs
  "RelSupports"       -> Just RelSupports
  "RelSets"           -> Just RelSets
  "RelNotJustCopies"  -> Just RelNotJustCopies
  _                   -> Nothing

instance FromJSON LoadedRelation where
  parseJSON = withObject "LoadedRelation" $ \o -> do
    from_ <- o .: "from"
    to_   <- o .: "to"
    type_ <- o .: "type"
    rt    <- case parseRelationType type_ of
               Just r  -> pure r
               Nothing -> fail ("Unknown relation type: " ++ T.unpack type_)
    LoadedRelation
      <$> pure from_
      <*> pure to_
      <*> pure rt
      <*> o .:? "verb"
      <*> o .:? "rationale"
      <*> o .:? "counter"
      <*> o .:? "synthesis"
      <*> o .:  "confidence"
      <*> o .:  "author"
      <*> o .:  "version"

instance ToJSON LoadedRelation where
  toJSON lr =
    object
      [ "from"       .= lrFrom lr
      , "to"         .= lrTo lr
      , "type"       .= T.pack (show (lrType lr))
      , "verb"       .= lrVerb lr
      , "rationale"  .= lrRationale lr
      , "counter"    .= lrCounter lr
      , "synthesis"  .= lrSynthesis lr
      , "confidence" .= lrConfidence lr
      , "author"     .= lrAuthor lr
      , "version"    .= lrVersion lr
      ]

-- ============================================================
-- Loading raw relations
-- ============================================================

-- | Load 'LoadedRelation' values from a JSONL file. Blank lines are
-- skipped; any parse error aborts via 'fail'.
loadRelations :: FilePath -> IO [LoadedRelation]
loadRelations path = do
  contents <- TIO.readFile path
  let rawLines = filter (not . T.null . T.strip) (T.lines contents)
  traverse parseLine rawLines
  where
    parseLine :: Text -> IO LoadedRelation
    parseLine line =
      case eitherDecodeStrict (TE.encodeUtf8 line) of
        Left err  -> fail ("Failed to parse relation line: " ++ err)
        Right rel -> pure rel

-- ============================================================
-- Atom lookup
-- ============================================================

-- | Reverse index from display text to 'AtomId'. Falls back to the
-- raw text (as its own id) when the display text is not present in
-- the curated atom store.
lookupAtomId :: Map Text AtomId -> Text -> AtomId
lookupAtomId displayIndex name =
  fromMaybe (AtomId name) (M.lookup name displayIndex)

-- | Build a display-text -> 'AtomId' map from the curated atom store.
atomDisplayIndex :: Map Text AtomId
atomDisplayIndex =
  M.fromList [ (atomDisplay a, atomId a) | (_, a) <- M.toList atomStore ]

-- ============================================================
-- Self-play relation admission gate
-- ============================================================

-- | Common Russian prepositions that LLM-generated relation endpoints
-- often prepend/append, turning nominative atoms into prepositional
-- phrases.  These are stripped before normalization.
russianPrepositions :: Set Text
russianPrepositions = S.fromList
  [ "в", "на", "с", "по", "для", "к", "о", "об", "обо", "от"
  , "до", "из", "за", "под", "над", "перед", "при", "про", "через"
  , "между"
  ]

-- | Morphology data derived from the curated atom store.  Maps each
-- atom's display text to its head noun so that 'toNominative' can
-- recover the nominative atom from a display phrase.
atomMorphologyData :: MorphologyData
atomMorphologyData = MorphologyData
  { mdPrepositional = M.empty
  , mdGenitive = M.empty
  , mdNominative = M.fromList
      [ (atomDisplay a, atomHead a)
      | (_, a) <- M.toList atomStore
      ]
  , mdFormsBySurface = M.empty
  }

-- | Strip leading and trailing Russian prepositions from a phrase.
stripEndPrepositions :: Text -> Text
stripEndPrepositions text =
  let words' = T.words text
      dropPrep = dropWhile (`S.member` russianPrepositions)
      stripped = reverse . dropPrep . reverse . dropPrep $ words'
  in T.unwords stripped

-- | Normalize a relation endpoint: trim whitespace, strip leading/trailing
-- prepositions, and convert to nominative using the atom-store morphology.
-- The result is the candidate nominative form that the admission gate
-- checks against the curated atom store.
normalizeRelationText :: Text -> Text
normalizeRelationText text =
  let stripped = T.strip (stripEndPrepositions (T.strip text))
  in T.strip (toNominative atomMorphologyData stripped)

-- | Check whether a normalized relation endpoint corresponds to a known
-- atom.  Matching uses the atom identifier, display text, or head noun.
admitRelationEndpoint :: Text -> Maybe Atom
admitRelationEndpoint text =
  let normalized = normalizeRelationText text
  in  M.lookup (AtomId normalized) atomStore
      <|> M.lookup normalized atomDisplayAtomMap
      <|> M.lookup normalized atomHeadAtomMap

-- | Display-text -> atom lookup.
atomDisplayAtomMap :: Map Text Atom
atomDisplayAtomMap =
  M.fromList [ (atomDisplay a, a) | (_, a) <- M.toList atomStore ]

-- | Head-noun -> atom lookup.
atomHeadAtomMap :: Map Text Atom
atomHeadAtomMap =
  M.fromList [ (atomHead a, a) | (_, a) <- M.toList atomStore ]

-- ============================================================
-- Relation graph
-- ============================================================

-- | Map a 'RelationType' to the grammatical case used for the object
-- in the project's existing verbalizer. This mirrors the case
-- annotations in 'QxFx0.Semantic.Content.AtomStore'.
objectCaseFor :: RelationType -> ObjectCase
objectCaseFor rt = case rt of
  RelPresupposes    -> CaseAccusative
  RelLimitedBy      -> CaseInstrumental
  RelRequires       -> CaseGenitive
  RelClaims         -> CaseAccusative
  RelVerifiedBy     -> CaseAccusative
  RelSignals        -> CasePrepositional
  RelTransformsInto -> CaseAccusative
  RelExpresses      -> CaseAccusative
  RelDiffersFrom    -> CaseGenitive
  RelRelatedTo      -> CaseInstrumental
  RelDirectedAt     -> CaseAccusative
  RelPreserves      -> CaseAccusative
  RelOrientsToward  -> CaseAccusative
  RelPrescribes     -> CaseAccusative
  RelBuiltThrough   -> CaseAccusative
  RelDenotes        -> CaseAccusative
  RelStructures     -> CaseAccusative
  RelDetermines     -> CaseAccusative
  RelTransforms     -> CaseAccusative
  RelGives          -> CaseAccusative
  RelReveals        -> CaseAccusative
  RelRecognizes     -> CaseAccusative
  RelUnifies        -> CaseAccusative
  RelConnects       -> CaseAccusative
  RelPrecedes       -> CaseDative
  RelDependsOn      -> CaseGenitive
  RelIncludes       -> CaseAccusative
  RelNecessaryFor   -> CaseGenitive
  RelEvokes         -> CaseAccusative
  RelMeans          -> CaseAccusative
  RelSays           -> CaseInstrumental
  RelNegates        -> CaseAccusative
  RelContrastsWith  -> CaseInstrumental
  RelNotReducibleTo -> CaseDative
  RelIsNot          -> CaseInstrumental
  RelCapableOf      -> CaseDative
  RelCreatedFrom    -> CaseGenitive
  RelReliesOn       -> CaseAccusative
  RelCanBe          -> CaseInstrumental
  RelDestroys       -> CaseAccusative
  RelPointsTo       -> CaseAccusative
  RelMakes          -> CaseAccusative
  RelIsA            -> CaseNominative
  RelReconstructs   -> CaseAccusative
  RelSupports       -> CaseAccusative
  RelSets           -> CaseAccusative
  RelNotJustCopies  -> CaseSpecial

-- | Convert a 'LoadedRelation' into the existing 'Relation' type,
-- resolving atom identifiers via the curated atom store.
toRelation :: Map Text AtomId -> LoadedRelation -> Relation
toRelation displayIndex lr =
  let fromId = lookupAtomId displayIndex (lrFrom lr)
      toId   = lookupAtomId displayIndex (lrTo lr)
  in Relation
      { relFrom       = fromId
      , relTo         = toId
      , relType       = lrType lr
      , relObjectCase = objectCaseFor (lrType lr)
      , relObjectText = lrTo lr
      , relVerbText   = lrVerb lr
      , relRuOriginal = ""
      , relEnOriginal = ""
      , relSource     = Curated
      , relTopic      = lrFrom lr
      , relRationale  = lrRationale lr
      , relCounter    = lrCounter lr
      , relSynthesis  = lrSynthesis lr
      }

-- | Sort relations canonically for deterministic graph order.
sortRelations :: [Relation] -> [Relation]
sortRelations =
  sortOn (\r -> (relFrom r, relTo r, show (relType r)))

-- | Build the from-atom index used by 'AtomGraph'.
buildIndex :: [Relation] -> Map AtomId [Relation]
buildIndex =
  foldl' (\acc r -> M.insertWith (++) (relFrom r) [r] acc) M.empty

-- | Load a relation graph from a JSONL file. The project does not
-- define a separate @RelationGraph@ type, so the existing
-- 'AtomGraph' is used as the graph structure.
loadRelationGraph :: FilePath -> IO AtomGraph
loadRelationGraph path = do
  rawRels <- loadRelations path
  let displayIdx = atomDisplayIndex
      rels       = sortRelations (map (toRelation displayIdx) rawRels)
  pure AtomGraph
    { agRelations = rels
    , agByFrom    = buildIndex rels
    , agVersion   = "ingest-v1"
    }

-- ============================================================
-- Semantic network
-- ============================================================

-- | Build a minimal 'SemanticNetwork' from a list of loaded relations
-- and an already-loaded ontology. All relation endpoints become
-- nodes, all ontology concepts become nodes, and every relation
-- becomes an explicit edge weighted by its confidence.
semanticNetworkFromLoaded
  :: Ontology -> [LoadedRelation] -> SemanticNetwork
semanticNetworkFromLoaded ont rawRels =
  let relationNodes = foldl' insertRelation S.empty rawRels
      ontologyNodes = S.fromList (map onName (M.elems (otNodes ont)))
      allNodes      = S.union relationNodes ontologyNodes
      edgeMap       = foldl' insertEdge M.empty rawRels
  in SemanticNetwork
      { snNodes         = allNodes
      , snEdges         = edgeMap
      , snActivation    = M.empty
      , snDecayRate     = 0.5
      , snMaxHops       = 3
      , snActivationLog = Seq.empty
      }
  where
    insertRelation :: Set Text -> LoadedRelation -> Set Text
    insertRelation acc lr = S.insert (lrFrom lr) (S.insert (lrTo lr) acc)

    insertEdge
      :: Map (Text, Text) SemanticEdge
      -> LoadedRelation
      -> Map (Text, Text) SemanticEdge
    insertEdge acc lr =
      let key = (lrFrom lr, lrTo lr)
          edge = SemanticEdge
            { seFrom         = lrFrom lr
            , seTo           = lrTo lr
            , seWeight       = lrConfidence lr
            , seCoOccurrence = 1
            , seSource       = ExplicitEdge
            , seRelationType = Just (lrType lr)
            , seVerb         = lrVerb lr
            , seRationale    = lrRationale lr
            , seCounter      = lrCounter lr
            , seSynthesis    = lrSynthesis lr
            , seConfidence   = lrConfidence lr
            , seProvenance   = ProvenanceIngested
            }
      in case M.lookup key acc of
           Nothing -> M.insert key edge acc
           Just old ->
             if seWeight edge > seWeight old
             then M.insert key edge acc
             else acc

-- | Build a 'SemanticNetwork' directly from an 'AtomGraph'. Each
-- 'Relation' becomes an explicit edge whose endpoints are the display
-- texts of the source and target atoms. Edge weight is derived from
-- 'relationTypeWeight'. If multiple relations share the same
-- @(from, to)@ pair, the edge with the higher weight is kept.
buildNetworkFromAtomGraph :: AtomGraph -> SemanticNetwork
buildNetworkFromAtomGraph g =
  let edges = foldl' insertEdge M.empty (agRelations g)
      nodes = foldl' insertNodes S.empty (M.elems edges)
  in SemanticNetwork
      { snNodes         = nodes
      , snEdges         = edges
      , snActivation    = M.empty
      , snDecayRate     = 0.5
      , snMaxHops       = 3
      , snActivationLog = Seq.empty
      }
  where
    insertNodes :: Set Text -> SemanticEdge -> Set Text
    insertNodes acc e = S.insert (seFrom e) (S.insert (seTo e) acc)

    insertEdge
      :: Map (Text, Text) SemanticEdge
      -> Relation
      -> Map (Text, Text) SemanticEdge
    insertEdge acc r =
      let fromText = atomDisplayFor (relFrom r)
          toText   = atomDisplayFor (relTo r)
          key      = (fromText, toText)
          w        = relationTypeWeight (relType r)
          edge     = SemanticEdge
            { seFrom         = fromText
            , seTo           = toText
            , seWeight       = w
            , seCoOccurrence = 1
            , seSource       = ExplicitEdge
            , seRelationType = Just (relType r)
            , seVerb         = relVerbText r
            , seRationale    = relRationale r
            , seCounter      = relCounter r
            , seSynthesis    = relSynthesis r
            , seConfidence   = w
            , seProvenance   = ProvenanceCurated
            }
      in case M.lookup key acc of
           Nothing -> M.insert key edge acc
           Just old ->
             if seWeight edge > seWeight old
             then M.insert key edge acc
             else acc

    atomDisplayFor :: AtomId -> Text
    atomDisplayFor aid =
      case M.lookup aid atomStore of
        Just a  -> atomDisplay a
        Nothing -> case aid of AtomId t -> t

-- | Ingest both the ontology and relation corpus, producing a
-- 'SemanticNetwork'. Any error prints a warning to @stderr@ and
-- returns 'Nothing'.
ingestExternalKnowledge :: FilePath -> FilePath -> IO (Maybe SemanticNetwork)
ingestExternalKnowledge ontologyPath relationsPath = do
  result <- try (do
    ont      <- loadOntology ontologyPath
    rawRels  <- loadRelations relationsPath
    pure (semanticNetworkFromLoaded ont rawRels)) :: IO (Either SomeException SemanticNetwork)
  case result of
    Right sn -> pure (Just sn)
    Left exc -> do
      hPutStrLn stderr ("Warning: ingestExternalKnowledge failed: " ++ show exc)
      pure Nothing

-- | Load self-play relations from a JSONL file. The format is identical
-- to the external relation corpus, but the expected author is
-- @"selfplay"@ and provenance is tracked separately.
loadSelfPlayRelations :: FilePath -> IO [LoadedRelation]
loadSelfPlayRelations = loadRelations

-- | Build a 'SemanticNetwork' from a list of self-play relations. All
-- relation endpoints become nodes and every relation becomes an
-- explicit edge with 'ProvenanceSelfPlay' and its loaded confidence.
semanticNetworkFromSelfPlay :: [LoadedRelation] -> SemanticNetwork
semanticNetworkFromSelfPlay rawRels =
  let nodes = foldl' insertRelation S.empty rawRels
      edgeMap = foldl' insertEdge M.empty rawRels
  in SemanticNetwork
      { snNodes         = nodes
      , snEdges         = edgeMap
      , snActivation    = M.empty
      , snDecayRate     = 0.5
      , snMaxHops       = 3
      , snActivationLog = Seq.empty
      }
  where
    insertRelation :: Set Text -> LoadedRelation -> Set Text
    insertRelation acc lr = S.insert (lrFrom lr) (S.insert (lrTo lr) acc)

    insertEdge
      :: Map (Text, Text) SemanticEdge
      -> LoadedRelation
      -> Map (Text, Text) SemanticEdge
    insertEdge acc lr =
      let key = (lrFrom lr, lrTo lr)
          edge = SemanticEdge
            { seFrom         = lrFrom lr
            , seTo           = lrTo lr
            , seWeight       = lrConfidence lr
            , seCoOccurrence = 1
            , seSource       = ExplicitEdge
            , seRelationType = Just (lrType lr)
            , seVerb         = lrVerb lr
            , seRationale    = lrRationale lr
            , seCounter      = lrCounter lr
            , seSynthesis    = lrSynthesis lr
            , seConfidence   = lrConfidence lr
            , seProvenance   = ProvenanceSelfPlay
            }
      in M.insert key edge acc

-- | Admitted relation with the endpoint texts replaced by the matched
-- atom display text.  This guarantees that self-play edges reference
-- only nominative atoms already present in the curated atom graph.
admitLoadedRelation :: LoadedRelation -> Maybe LoadedRelation
admitLoadedRelation lr = do
  fromAtom <- admitRelationEndpoint (lrFrom lr)
  toAtom   <- admitRelationEndpoint (lrTo lr)
  pure lr
    { lrFrom = atomDisplay fromAtom
    , lrTo   = atomDisplay toAtom
    }

-- | Emit a warning for a rejected self-play relation.
warnRejectedRelation :: LoadedRelation -> IO ()
warnRejectedRelation lr =
  hPutStrLn stderr $
    "Warning: rejecting self-play relation (not in atom store): "
    ++ T.unpack (lrFrom lr) ++ " -> " ++ T.unpack (lrTo lr)

-- | Load self-play relations from a file, apply the admission gate to
-- each endpoint, and merge the admitted relations into an existing
-- 'SemanticNetwork'.  Relations whose normalized endpoints are not in
-- the curated atom store are skipped and logged.  Merging uses
-- 'mergeSemanticNetworks', so collisions are resolved by provenance
-- authority and confidence.
mergeSelfPlayRelations :: FilePath -> SemanticNetwork -> IO SemanticNetwork
mergeSelfPlayRelations path baseNetwork = do
  rawRels <- loadSelfPlayRelations path
  let classified = map (\lr -> (lr, admitLoadedRelation lr)) rawRels
      admitted   = mapMaybe snd classified
      rejected   = [ lr | (lr, Nothing) <- classified ]
  mapM_ warnRejectedRelation rejected
  let selfplayNetwork = semanticNetworkFromSelfPlay admitted
  pure $ mergeSemanticNetworks baseNetwork selfplayNetwork
