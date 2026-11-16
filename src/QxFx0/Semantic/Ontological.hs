{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.Ontological
Description : observer — deterministic v1 classifier of the utterance's ontological directedness (concept v3 §5).

@classifyOntological@ projects one utterance onto the three category
pairs of 'OntologicalVector' via fixed marker lexicons.  Each axis is
the total-count-normalized balance

@
axis = (posHits − negHits) / max 1 (posHits + negHits)
@

so the result is bounded by construction and zero when no markers
fire (a philosophical question carries no ontological act — the
concept v3 §9 decoy requirement).

Negation safety uses the same replace-then-count discipline as the
R5 encoder: negative phrases are blanked out before positive
markers are counted, so \"не хочу\" never counts as striving+.

Mention is not use (math version 6): a /report/ of someone else's
claim is not the speaker's act.  'isReport' detects quotation, report
phrases and third-party attributions, and a report resolves the whole
utterance to 'neutralOntologicalVector' — the measured defect was
«… — так утверждал Шопенгауэр?» reading as the user's own being−.
The rule is deliberately blunt because the attribution may follow the
claim; a first-person token vetoes the attribution-verb branch, so the
speaker's own act survives inside a report («…, но я так не думаю»).

'resonanceGateThreshold' / 'ontologicalMoveAdmissible' implement the
concept v3 §5 /resonance threshold/: the operator of affirmation of
being may be applied only when the user's resonance is above the
gate.  Order of moves — mirror the state, establish resonance, then
make the ontological move — is the move-graph's concern; this
predicate is the pure gate it will consume.
-}
module QxFx0.Semantic.Ontological
  ( classifyOntological
  , isReport
  , resonanceGateThreshold
  , ontologicalMoveAdmissible
    -- * Marker lexicons (exported for tests and audit)
  , beingPositiveMarkers
  , beingNegativeMarkers
  , strivingPositiveMarkers
  , strivingNegativeMarkers
  , affirmationPositiveMarkers
  , affirmationNegativeMarkers
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Semantic.OntologicalAxis
import QxFx0.Types.User.R5 (UserR5State (..))
import QxFx0.Semantic.Markers
  ( beingPositiveMarkers
  , beingNegativeMarkers
  , strivingPositiveMarkers
  , strivingNegativeMarkers
  , affirmationPositiveMarkers
  , affirmationNegativeMarkers
  )

-- | Classify the ontological directedness of one utterance.  Total
-- and deterministic; empty and marker-free input yields
-- 'neutralOntologicalVector'.  A report of a third party's claim
-- yields the neutral vector too ('isReport').
classifyOntological :: Text -> OntologicalVector
classifyOntological raw
  | isReport raw = neutralOntologicalVector
  | otherwise = mkOntologicalVector being striving affirmation
  where
    norm = normalizeText raw
    being = axisOf norm beingPositiveMarkers beingNegativeMarkers
    striving = axisOf norm strivingPositiveMarkers strivingNegativeMarkers
    affirmation = axisOf norm affirmationPositiveMarkers affirmationNegativeMarkers
    -- Negation safety: negative phrases are counted and blanked out
    -- before positive markers fire ("не хочу" is not striving+).
    axisOf text pos neg =
      let negHits = fromIntegral (countAny text neg)
          cleaned = blankAll text neg
          posHits = fromIntegral (countAny cleaned pos)
          total = posHits + negHits
      in if total <= 0 then 0.0 else (posHits - negHits) / total
    countAny text markers =
      length (filter (`T.isInfixOf` text) markers)
    blankAll text markers =
      foldr (\m acc -> T.replace m " § " acc) text markers

-- | Is the utterance /reporting/ someone else's claim rather than
-- making one?  Hand-set v1 (math version 6), lexical by construction.
--
-- A report is an utterance that
--
-- * contains a quotation mark — a quoted span is a mention by
--   construction;
-- * carries an unambiguous report phrase (@по мнению@, @по словам@,
--   @согласно@, @цитата@, @говорят@);
-- * carries a third-party report verb (@писал@, @считал@,
--   @утверждал@, …) with a name-like capitalized token within two
--   positions, or a third-person pronoun — unless a first-person
--   token is present, in which case the act stays the speaker's.
--
-- Deliberately blunt: the whole utterance resolves to neutral,
-- because the measured form puts the attribution /after/ the claim
-- («… — так утверждал Шопенгауэр»), so clause-level blanking would
-- keep the claim and fix nothing.  Known limits: a report plus a
-- genuine act in one utterance without a first-person token resolves
-- to neutral, and impersonal forms («сказано, что…») are not caught.
isReport :: Text -> Bool
isReport raw =
  let rawTokens = T.words raw
      tokens = map cleanToken rawTokens
      norm = T.intercalate " " tokens
  in hasQuote raw
     || any (`T.isInfixOf` norm) attributionPhrases
     || attributedToThirdParty rawTokens tokens

-- | Quote characters: a quoted span is a mention by construction.
hasQuote :: Text -> Bool
hasQuote = T.any (`elem` quoteChars)

-- | Lowercase, ё→е, whitespace-normalize — the same discipline as the
-- R5 encoder, so markers match regardless of case and spacing.
normalizeText :: Text -> Text
normalizeText = T.intercalate " " . T.words . T.replace "ё" "е" . T.toLower

-- | Lowercase a token and strip the punctuation the predictor strips,
-- so token equality is not broken by a trailing comma.
cleanToken :: Text -> Text
cleanToken =
  T.dropAround (`elem` tokenPunctuation)
    . T.replace "ё" "е"
    . T.toLower

-- | The attribution-verb branch: a verb with a name-like subject or a
-- third-person pronoun, vetoed by a first-person token.
attributedToThirdParty :: [Text] -> [Text] -> Bool
attributedToThirdParty rawTokens tokens
  | null verbIndices = False
  | any (`elem` firstPersonWords) tokens = False
  | any (`elem` thirdPersonWords) tokens = True
  | otherwise = or
      [ isCapitalizedName (stripToken rawToken)
          && any (\verbIndex -> abs (index - verbIndex) <= 2) verbIndices
      | (index, rawToken) <- zip [0 ..] rawTokens
      ]
  where
    verbIndices =
      [ index
      | (index, token) <- zip [0 ..] tokens
      , token `elem` attributionVerbs
      ]

-- | Name-like token: an uppercase initial followed by at least one
-- lowercase letter or hyphen — the predictor's @[А-ЯЁA-Z][а-яёa-z-]+@.
isCapitalizedName :: Text -> Bool
isCapitalizedName token =
  case T.uncons token of
    Nothing -> False
    Just (initial, rest) ->
      isCapitalInitial initial
        && not (T.null rest)
        && T.all (\ch -> isNameChar ch || ch == '-') rest

isCapitalInitial :: Char -> Bool
isCapitalInitial ch =
  (ch >= 'А' && ch <= 'Я') || ch == 'Ё' || (ch >= 'A' && ch <= 'Z')

isNameChar :: Char -> Bool
isNameChar ch = (ch >= 'а' && ch <= 'я') || ch == 'ё' || (ch >= 'a' && ch <= 'z')

stripToken :: Text -> Text
stripToken = T.dropAround (`elem` tokenPunctuation)

tokenPunctuation :: [Char]
tokenPunctuation = ".,!?;:—–«»\"()"

quoteChars :: [Char]
quoteChars = ['«', '»', '„', '“', '”', '"']

-- | Third-party report verbs.  Deliberately finite: the measured
-- defect class is a doctrinal attribution («так утверждал
-- Шопенгауэр», «Камю писал»).
attributionVerbs :: [Text]
attributionVerbs =
  [ "писал", "писала", "считал", "считала", "говорил", "говорила"
  , "утверждал", "утверждала", "учил", "учила", "называл", "называла"
  , "полагал", "полагала", "доказывал", "замечал", "отмечал", "думал"
  ]

-- | Report phrases: they carry the attribution themselves.
attributionPhrases :: [Text]
attributionPhrases =
  [ "по мнению", "по словам", "согласно", "цитата", "говорят" ]

-- | First-person tokens.  A speaker present in the utterance is not a
-- report, even when the utterance also quotes someone.
firstPersonWords :: [Text]
firstPersonWords =
  [ "я", "мне", "меня", "мой", "моя", "мое", "мы", "нас", "наш" ]

-- | Third-person pronouns that can carry the attribution subject.
thirdPersonWords :: [Text]
thirdPersonWords = [ "он", "она", "они", "его", "ее", "их" ]

-- | The resonance gate for applying the affirmation-of-being
-- operator (concept v3 §5).  Hand-set v1; calibration against
-- labelled dialogue is a later, governed phase.
resonanceGateThreshold :: Double
resonanceGateThreshold = 0.55

-- | May the ontological move (the counter-vector of affirmation of
-- being) be applied given the user's current resonance?  Below the
-- gate the system must first mirror the state and establish
-- resonance — applying the move too early reads as cold rejection
-- and pushes the receiver deeper into non-being.
ontologicalMoveAdmissible :: UserR5State -> Bool
ontologicalMoveAdmissible userState =
  r5Resonance userState > resonanceGateThreshold
