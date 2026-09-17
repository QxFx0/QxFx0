{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Composition
Description : canonical — typed atomic terms and structural scoring (v1).

Replaces role-blind Jaccard/set-overlap scoring with a minimal
compositional match: atoms carry roles (Concept \/ Relation \/
Modifier \/ Negation), a predicate parses to a 'PredicateTerm'
(head-concept, relation pairs, modifiers, negation flag), and
'structScore' matches query-against-predicate structurally.

Status (2026-09-16): SHADOW ONLY.  Nothing in the runtime calls
'structScore' for decisions; 'scorePred', 'stanceSimilarity' and
the Jaccard paths are untouched.  Cutover requires a corpus win
(top-1 accuracy >= Jaccard + 0.05 on human-labelled holdout) plus
a 'selectorMathVersion' bump — see docs\/closure\/CALIBRATION_CORPUS.md.

Role tagging is deterministic and total:

  * negation markers are checked FIRST (blank-then-count discipline,
    cf. R5 'encodeR5' and 'classifyOntological'): «не хочу» records
    @ptNeg = True@ and the marker never enters any set.
  * relation verbs come from the closed v1 'relationLexicon'
    (frozen; extension is a math-version change).
  * concepts keep short roots («зло», «я»): unlike
    'tokenizePredicate' (Space.hs, drops len<=3) there is no length
    filter here — the length cutoff was the documented Jaccard-era
    loss channel.
  * stopwords are dropped only after role tagging and never shadow Relation\/Negation
    (copulas like «является» are deliberately NOT relations).

'structScore' is directional: relation\/modifier overlap is
query-covered-by-predicate (@|q ∩ p| \/ max 1 |q|@), so a question
about X matched by a predicate about X+Y scores high, not vice
versa.  Range [0,1] under default weights (head=0.5, rel=0.3, mod=0.15, neg=0.05).
-}
module QxFx0.Semantic.Composition
  ( -- * Roles and terms
    AtomRole(..)
  , PredicateTerm(..)
  , parsePredicateTerm
    -- * Lexicons (frozen v1)
  , relationLexicon
  , negationMarkers
  , compositionStopWords
  , relationLexiconVersion
  , stemMatchesLexicon
    -- * Weights (hand-set v1, calibratable — group 3)
  , StructWeights(..)
  , defaultStructWeights
  , structScoreWith
    -- * Scoring
  , structScore
  , jaccardBaseline
  ) where

import Control.DeepSeq (NFData)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Role of a lemmatized atom inside a predicate term.
data AtomRole
  = RoleConcept
  | RoleRelation
  | RoleModifier
  | RoleNegation
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (NFData)

-- | A predicate parsed into typed structure.  Total: every surface,
-- including the empty text, yields a term (possibly headless).
data PredicateTerm = PredicateTerm
  { ptHead :: !(Maybe Text)
    -- ^ First concept token in surface order ('Nothing' when the
    --   surface carries no concept, e.g. stopwords-only input).
  , ptRels :: !(Set (Text, Text))
    -- ^ Relation pairs @(verb, object-concept)@; the object is the
    --   nearest following concept, else the head.
  , ptMods :: !(Set Text)
    -- ^ Concept tokens that are neither the head-concept nor relation objects.
  , ptNeg  :: !Bool
    -- ^ Negation marker present (markers never enter any set).
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Frozen v1 relation lexicon (lemmatized forms).  Extension is a
-- math-version change, not an edit.
relationLexiconVersion :: Text
relationLexiconVersion = "relation-lexicon-v1"

-- | Content relation verbs.  Copulas («является», «есть», «быть»)
-- are excluded: they carry no relational content.
relationLexicon :: Set Text
relationLexicon = S.fromList
  [ "требовать", "предполагать", "ограничивать", "означать"
  , "связать", "вести", "давать", "делать", "становиться"
  , "оставаться", "служить", "выражать", "отражать", "определять"
  , "зависеть", "противоречить", "совпадать", "различать"
  , "соединять", "порождать", "влечь", "исключать", "включать"
  , "превращать"
  ]

-- | Negation markers, checked before stopword removal.
negationMarkers :: Set Text
negationMarkers = S.fromList ["не", "ни", "нет", "без"]

-- | Stem fallback for relation matching (v1, frozen rule).
--
-- The morphology resource is nouns-only (20000 + 38 paradigms, zero
-- verbs), so the lemma map never produces verb infinitives:
-- «требует»\/«ограничена» are unknown words, not relations.  Without
-- a fallback, term-level relation tagging is dead (measured 0\/24
-- lexicon verbs attested on the corpus) and only path verbs
-- ('relTypeVerb') carry relation content.
--
-- Rule: a token unknown to the lemma map (i.e. NOT a known noun —
-- «требование» stays a concept) counts as a relation verb when it
-- shares a common prefix of length >= 4 with a lexicon infinitive (token itself >= 5 chars)
-- («требует»\/«требовать», «ограничена»\/«ограничивать»).  Same
-- tolerance discipline as 'inflectedWordMatch' (ResponsePlan.hs);
-- short-prefix verbs («даёт»\/«давать») stay unreachable — that gap
-- needs real verb paradigms, not a looser rule.
stemMatchesLexicon :: Set Text -> Text -> Bool
stemMatchesLexicon lemmaKeys token
  | token `S.member` lemmaKeys = False
  | otherwise = any (commonPrefixAtLeast5 token) (S.toList relationLexicon)
  where
    commonPrefixAtLeast5 a b =
      T.length a >= 5
        && length (takeWhile (uncurry (==)) (zip (T.unpack a) (T.unpack b))) >= 4

-- | Closed v1 stopword list.  Deliberately separate from the Space.hs
-- inline list (which also drops «не»\/«ни» and len<=3 tokens — exactly
-- the channels this module reopens); the two lists serve different
-- scoring regimes and must not be silently unified.
compositionStopWords :: Set Text
compositionStopWords = S.fromList
  [ "это", "есть", "является", "быть", "было", "будет"
  , "и", "или", "но", "а", "в", "на", "с", "по", "для"
  , "что", "как", "когда", "где", "кто", "который", "которая"
  , "же", "ли", "бы", "то", "так", "только", "все", "вся"
  , "весь", "всех", "такой", "такая", "между", "через", "при"
  , "уже", "даже", "если", "пусть", "можно", "нельзя"
  ]

-- | Parse a surface into a 'PredicateTerm' under a lemma map.
-- Pure, total, deterministic.
parsePredicateTerm :: Map Text Text -> Text -> PredicateTerm
parsePredicateTerm lemmaMap text =
  let toks = [ M.findWithDefault w w lemmaMap
             | w <- map clean (T.words (T.toLower text))
             , not (T.null w) ]
      neg = any (`S.member` negationMarkers) toks
      core = [ t | t <- toks
             , not (t `S.member` negationMarkers)
             , not (t `S.member` compositionStopWords) ]
      isRel t = t `S.member` relationLexicon
                || stemMatchesLexicon (M.keysSet lemmaMap) t
      concepts = [ t | t <- core, not (isRel t) ]
      headTok = case concepts of
                  (h : _) -> Just h
                  []      -> Nothing
      rels = S.fromList
        [ (r, obj)
        | (i, r) <- zip [0 :: Int ..] core
        , isRel r
        , let following = [ c | c <- drop (i + 1) core
                          , not (isRel c) ]
              obj = case following of
                      (c : _) -> c
                      []      -> case headTok of
                                   Just h  -> h
                                   Nothing -> r
        ]
      relObjs = S.fromList [ o | (_, o) <- S.toList rels ]
      mods = S.fromList
        [ c | c <- concepts
        , Just c /= headTok
        , not (c `S.member` relObjs) ]
  in PredicateTerm
       { ptHead = headTok
       , ptRels = rels
       , ptMods = mods
       , ptNeg  = neg
       }
  where
    clean = T.filter (\c -> c /= '.' && c /= ',' && c /= '?'
                         && c /= '!' && c /= ':' && c /= ';'
                         && c /= '"' && c /= '«' && c /= '»'
                         && c /= '(' && c /= ')')

-- | Hand-set v1 weights for 'structScoreWith'.  Every field is
-- pinned in @data\/calibration\/ranges.json@ (codomain [0,1]) and
-- belongs to calibration group 3 (coordinate ascent on top-1
-- accuracy); changing a default requires a math-version bump.
data StructWeights = StructWeights
  { swHead :: !Double
  , swRel  :: !Double
  , swMod  :: !Double
  , swNeg  :: !Double
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Hand-set v1 defaults: @0.5\/0.3\/0.15\/0.05@.  Head identity
-- dominates (a predicate about another head-concept is a miss); relations
-- beat modifiers; negation agreement is a tie-break, never a driver.
defaultStructWeights :: StructWeights
defaultStructWeights = StructWeights
  { swHead = 0.5
  , swRel = 0.3
  , swMod = 0.15
  , swNeg = 0.05
  }

-- | Structural match of a query term against a predicate term.
-- Directional on relations\/modifiers (query covered by predicate).
-- Range [0,1] under the default weights.
structScore :: PredicateTerm -> PredicateTerm -> Double
structScore = structScoreWith defaultStructWeights

-- | 'structScore' under explicit weights (the calibration entry point).
structScoreWith :: StructWeights -> PredicateTerm -> PredicateTerm -> Double
structScoreWith w q p =
  let headScore = case (ptHead q, ptHead p) of
        (Just h1, Just h2) -> if h1 == h2 then 1.0 else 0.0
        _                  -> 0.0
      relScore =
        let qi = ptRels q
        in if S.null qi then 0.0
           else fromIntegral (S.size (S.intersection qi (ptRels p)))
              / fromIntegral (S.size qi)
      modScore =
        let qm = ptMods q
        in if S.null qm then 0.0
           else fromIntegral (S.size (S.intersection qm (ptMods p)))
              / fromIntegral (S.size qm)
      negScore = if ptNeg q == ptNeg p then 1.0 else 0.0
  in swHead w * headScore + swRel w * relScore
     + swMod w * modScore + swNeg w * negScore

-- | The Jaccard-era baseline over raw concept sets, kept so the
-- corpus divergence report can quote both numbers side by side.
-- Deliberately role-blind: this is the regime under replacement.
jaccardBaseline :: PredicateTerm -> PredicateTerm -> Double
jaccardBaseline a b =
  let sa = termConcepts a
      sb = termConcepts b
      u = S.size (S.union sa sb)
  in if u == 0 then 0.0
     else fromIntegral (S.size (S.intersection sa sb)) / fromIntegral u
  where
    termConcepts t =
      S.fromList ([h | Just h <- [ptHead t]]
                  ++ [o | (_, o) <- S.toList (ptRels t)]
                  ++ S.toList (ptMods t))
