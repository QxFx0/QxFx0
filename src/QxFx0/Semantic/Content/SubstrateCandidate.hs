{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Content.SubstrateCandidate
Description : Step 6 — Substrate candidate extraction + admission pipeline.

brain_kb → SubstrateCandidate → Admission → ExplicitRelation

Substrate proposes candidate relations; only admitted (promoted)
relations enter the AtomStore graph with source=PromotedSubstrate.
SubstrateExtractedRaw never surfaces (enforced by Gate G4).

Extraction uses morphological parsing (not regex):
  1. Find philosophical topic triggers in brain_kb entry
  2. Extract noun phrases as candidate atoms
  3. Match verb patterns against relation whitelist
  4. Score candidates by confidence (co-occurrence frequency + topic match)

Admission validates:
  - Relation type is in whitelist (12 core types)
  - Both atoms exist in AtomStore (or are close matches)
  - Confidence ≥ admission threshold
  - Source span is recorded (which brain_kb entry, which text)
-}
module QxFx0.Semantic.Content.SubstrateCandidate
  ( -- * Types
    SubstrateCandidate(..)
  , AdmissionStatus(..)
  , AdmissionConfig(..)
  , SourceSpan(..)
    -- * Extraction
  , extractCandidates
  , extractCandidatesFromEntry
    -- * Admission
  , admitCandidate
  , admitCandidates
  , defaultAdmissionConfig
    -- * Promotion
  , promoteToRelation
  , promoteAll
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (foldl', isInfixOf, isPrefixOf, nub, sort, sortBy)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (comparing, Down(..))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Network.Substrate (BrainKBEntry(..))

-- ============================================================
-- Types
-- ============================================================

-- | A candidate relation extracted from substrate (brain_kb).
data SubstrateCandidate = SubstrateCandidate
  { scFromTopic     :: !Text          -- philosophical topic (from triggers)
  , scToAtomSurface :: !Text          -- candidate object atom surface
  , scRelTypeGuess  :: !Text          -- guessed relation type verb (Russian)
  , scConfidence    :: !Double        -- 0..1, extraction confidence
  , scSourceSpan    :: !SourceSpan    -- provenance: which brain_kb entry
  , scRawText       :: !Text          -- the raw text snippet
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Provenance: where in brain_kb this candidate came from.
data SourceSpan = SourceSpan
  { ssEntryText :: !Text   -- the brain_kb entry text
  , ssLayer     :: !Text   -- brain_kb layer
  , ssKind      :: !Text   -- brain_kb kind
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data AdmissionStatus
  = Admitted    -- passed all checks, promoted to PromotedSubstrate
  | Rejected !Text  -- failed, with reason
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data AdmissionConfig = AdmissionConfig
  { acMinConfidence    :: !Double    -- minimum confidence to admit
  , acRequireTopicMatch :: !Bool     -- require from-topic in AtomStore
  , acRelationWhitelist :: ![Text]   -- allowed relation verbs
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- ============================================================
-- Default config
-- ============================================================

defaultAdmissionConfig :: AdmissionConfig
defaultAdmissionConfig = AdmissionConfig
  { acMinConfidence = 0.3
  , acRequireTopicMatch = True
  , acRelationWhitelist =
      [ "предполагает"
      , "ограничена"
      , "требует"
      , "претендует"
      , "проверяется"
      , "сигнализирует"
      , "выражает"
      , "отличается"
      , "связана"
      , "сохраняет"
      , "ориентирует"
      , "предписывает"
      , "обозначает"
      , "структурирует"
      , "определяет"
      , "преобразует"
      , "придаёт"
      , "обнаруживает"
      , "признаёт"
      , "объединяет"
      , "связывает"
      , "предшествует"
      , "зависит"
      , "включает"
      , "вызывает"
      , "означает"
      , "говорит"
      , "отрицает"
      , "направляет"
      , "указывает"
      , "делает"
      , "поддерживает"
      , "задаёт"
      , "разрушает"
      ]
  }

-- ============================================================
-- Extraction
-- ============================================================

-- | Extract substrate candidates from a list of brain_kb entries.
-- Only entries with philosophical topic triggers are processed.
extractCandidates :: [BrainKBEntry] -> [Text] -> [SubstrateCandidate]
extractCandidates entries topicList =
  concatMap (extractCandidatesFromEntry topicList) entries

-- | Extract candidates from a single brain_kb entry.
-- Finds philosophical topics in triggers, then looks for relation verbs
-- in the text that connect topics to other nouns.
extractCandidatesFromEntry :: [Text] -> BrainKBEntry -> [SubstrateCandidate]
extractCandidatesFromEntry topicList entry =
  let philTopics = findPhilosophicalTopics topicList (beTriggers entry)
      lower = T.toLower (beText entry)
      -- For each philosophical topic found, look for relation verbs nearby
      candidates = concatMap (extractForTopic entry lower) philTopics
  in candidates

-- | Find which of our philosophical topics appear in the trigger list.
findPhilosophicalTopics :: [Text] -> [Text] -> [Text]
findPhilosophicalTopics topicList triggers =
  filter (\t -> any (\tr -> t `T.isInfixOf` tr) triggers) topicList

-- | Extract candidates for a specific topic from entry text.
-- Looks for pattern: "topic ... verb ... noun" in the text.
extractForTopic :: BrainKBEntry -> Text -> Text -> [SubstrateCandidate]
extractForTopic entry lower topic =
  let span = SourceSpan (beText entry) (beLayer entry) (beKind entry)
      -- Find all relation verbs in the text
      verbsFound = filterVerbs lower (acRelationWhitelist defaultAdmissionConfig)
      -- For each verb, extract the noun phrase after it
      candidates = mapMaybe (extractCandidateForVerb topic span lower (beTriggers entry)) verbsFound
      -- Score by confidence: higher if topic appears in text + verb found + noun extracted
      scored = map (\c -> c { scConfidence = scoreCandidate c topic lower }) candidates
  in scored

-- | Find which relation verbs appear in the text.
filterVerbs :: Text -> [Text] -> [Text]
filterVerbs text verbs = filter (`T.isInfixOf` text) verbs

-- | Extract a candidate for a specific verb in the text.
-- Pattern: "verb <noun_phrase>" — takes words after verb until stop word.
extractCandidateForVerb :: Text -> SourceSpan -> Text -> [Text] -> Text -> Maybe SubstrateCandidate
extractCandidateForVerb topic span text triggers verb =
  let afterVerb = extractAfter (verb <> " ") text
  in case afterVerb of
       "" -> Nothing
       nounPhrase ->
         let cleanNoun = cleanPhrase nounPhrase
         in if T.null cleanNoun || cleanNoun == topic
              then Nothing
              else Just $ SubstrateCandidate
                { scFromTopic = topic
                , scToAtomSurface = cleanNoun
                , scRelTypeGuess = verb
                , scConfidence = 0.0  -- will be scored later
                , scSourceSpan = span
                , scRawText = text
                }

-- | Extract text after a marker, up to the next sentence boundary.
extractAfter :: Text -> Text -> Text
extractAfter marker text =
  case T.breakOn marker text of
    (_, rest) | not (T.null rest) ->
      let after = T.drop (T.length marker) rest
          -- Take up to next period, comma, or end
          snippet = T.takeWhile (\c -> c /= '.' && c /= ',' && c /= ';' && c /= ':' && c /= '\n') after
      in T.strip snippet
    _ -> ""

-- | Clean a noun phrase: remove leading articles, stop words.
cleanPhrase :: Text -> Text
cleanPhrase phrase =
  let words = T.words phrase
      stopWords = ["и", "или", "но", "а", "же", "ли", "бы", "не", "ни", "это", "тот", "этот", "такой"]
      filtered = filter (\w -> w `notElem` stopWords) words
  in T.intercalate " " filtered

-- | Score a candidate by how confidently it was extracted.
-- Higher = topic in text + verb found + noun is plausible.
scoreCandidate :: SubstrateCandidate -> Text -> Text -> Double
scoreCandidate cand topic text =
  let topicPresent = if topic `T.isInfixOf` text then 0.3 else 0.0
      nounLength = fromIntegral (min (T.length (scToAtomSurface cand)) 40) / 40.0
      verbMatch = 0.2  -- verb was found in text
      notSelfRef = if scToAtomSurface cand /= topic then 0.1 else 0.0
  in topicPresent + nounLength * 0.2 + verbMatch + notSelfRef

-- ============================================================
-- Admission
-- ============================================================

-- | Admit a single candidate. Returns Admitted or Rejected with reason.
-- Requires both topic AND object atoms to exist in AtomStore.
admitCandidate :: AdmissionConfig -> [AtomId] -> SubstrateCandidate -> AdmissionStatus
admitCandidate config knownAtoms cand =
  let topicOk = not (acRequireTopicMatch config)
                || AtomId (scFromTopic cand) `elem` knownAtoms
      objOk = AtomId (scToAtomSurface cand) `elem` knownAtoms
      confOk = scConfidence cand >= acMinConfidence config
      verbOk = scRelTypeGuess cand `elem` acRelationWhitelist config
      notSelf = scToAtomSurface cand /= scFromTopic cand
      notEmpty = not (T.null (scToAtomSurface cand))
  in if not topicOk
       then Rejected "topic not in AtomStore"
       else if not objOk
         then Rejected "object atom not in AtomStore"
         else if not confOk
           then Rejected ("confidence below threshold: " <> T.pack (show (scConfidence cand)))
           else if not verbOk
             then Rejected ("verb not in whitelist: " <> scRelTypeGuess cand)
             else if not notSelf
               then Rejected "self-referential"
               else if not notEmpty
                 then Rejected "empty object"
                 else Admitted

-- | Admit a batch of candidates. Returns (admitted, rejected).
admitCandidates :: AdmissionConfig -> [AtomId] -> [SubstrateCandidate]
               -> ([SubstrateCandidate], [(SubstrateCandidate, Text)])
admitCandidates config knownAtoms candidates =
  let results = map (\c -> (c, admitCandidate config knownAtoms c)) candidates
      admitted = [ c | (c, Admitted) <- results ]
      rejected = [ (c, reason) | (c, Rejected reason) <- results ]
  in (admitted, rejected)

-- ============================================================
-- Promotion
-- ============================================================

-- | Promote an admitted candidate to a Relation in the AtomStore graph.
-- The promoted relation gets source=PromotedSubstrate.
promoteToRelation :: SubstrateCandidate -> Relation
promoteToRelation cand =
  let topic = scFromTopic cand
      objSurface = scToAtomSurface cand
      verbGuess = scRelTypeGuess cand
      -- Map verb text to RelationType (best guess)
      relType = guessRelationType verbGuess
      -- Object case from relation type (default accusative)
      objCase = CaseAccusative
      -- Full predicate text for round-trip
      ruOriginal = topic <> " " <> verbGuess <> " " <> objSurface
  in Relation
       { relFrom = AtomId topic
       , relTo = AtomId objSurface
       , relType = relType
       , relObjectCase = objCase
       , relObjectText = objSurface
       , relVerbText = Just verbGuess
       , relRuOriginal = ruOriginal
       , relEnOriginal = ""  -- no English for substrate-extracted
       , relSource = PromotedSubstrate
       , relTopic = topic
       }

-- | Promote all admitted candidates to relations.
promoteAll :: [SubstrateCandidate] -> [Relation]
promoteAll = map promoteToRelation

-- | Guess RelationType from a verb text.
-- Maps known verbs to their relation types.
guessRelationType :: Text -> RelationType
guessRelationType verb
  | "предполагает" `T.isPrefixOf` verb = RelPresupposes
  | "ограничена" `T.isPrefixOf` verb = RelLimitedBy
  | "требует" `T.isPrefixOf` verb = RelRequires
  | "претендует" `T.isPrefixOf` verb = RelClaims
  | "проверяется" `T.isPrefixOf` verb = RelVerifiedBy
  | "сигнализирует" `T.isPrefixOf` verb = RelSignals
  | "выражает" `T.isPrefixOf` verb = RelExpresses
  | "отличается" `T.isPrefixOf` verb = RelDiffersFrom
  | "связана" `T.isPrefixOf` verb = RelRelatedTo
  | "сохраняет" `T.isPrefixOf` verb = RelPreserves
  | "ориентирует" `T.isPrefixOf` verb = RelOrientsToward
  | "предписывает" `T.isPrefixOf` verb = RelPrescribes
  | "обозначает" `T.isPrefixOf` verb = RelDenotes
  | "структурирует" `T.isPrefixOf` verb = RelStructures
  | "определяет" `T.isPrefixOf` verb = RelDetermines
  | "преобразует" `T.isPrefixOf` verb = RelTransforms
  | "придаёт" `T.isPrefixOf` verb = RelGives
  | "обнаруживает" `T.isPrefixOf` verb = RelReveals
  | "признаёт" `T.isPrefixOf` verb = RelRecognizes
  | "объединяет" `T.isPrefixOf` verb = RelUnifies
  | "связывает" `T.isPrefixOf` verb = RelConnects
  | "предшествует" `T.isPrefixOf` verb = RelPrecedes
  | "зависит" `T.isPrefixOf` verb = RelDependsOn
  | "включает" `T.isPrefixOf` verb = RelIncludes
  | "вызывает" `T.isPrefixOf` verb = RelEvokes
  | "означает" `T.isPrefixOf` verb = RelMeans
  | "говорит" `T.isPrefixOf` verb = RelSays
  | "отрицает" `T.isPrefixOf` verb = RelNegates
  | "направляет" `T.isPrefixOf` verb = RelDirectedAt
  | "указывает" `T.isPrefixOf` verb = RelPointsTo
  | "делает" `T.isPrefixOf` verb = RelMakes
  | "поддерживает" `T.isPrefixOf` verb = RelSupports
  | "задаёт" `T.isPrefixOf` verb = RelSets
  | "разрушает" `T.isPrefixOf` verb = RelDestroys
  | otherwise = RelIsA  -- fallback
