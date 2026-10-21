{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Safety.CrisisGuard
Description : canonical — hard lexical crisis guardrail (Protocol B) per concept v3 §2.

The guard implements the /hard/ half of the two-protocol law:

* 'detectCrisisTrigger' matches acute lexical markers on the
  normalized input.  The lexicon is high-precision by design: it
  contains only unambiguous acute statements (suicidal ideation,
  self-harm).  Philosophical pessimism (\"жизнь бессмысленна\" as a
  position), dark humour, and tiredness are deliberately absent —
  those belong to 'ProtocolA' and the R5 viability contour
  ('QxFx0.Types.User.R5'), not to the hard gate.

* 'decideProtocol' resolves the per-turn verdict: a hard trigger
  forces 'ProtocolB' regardless of any numeric score (concept v3 §2:
  \"Ворота не доверяют модели\"); without a trigger, only a contour
  exit can force 'ProtocolB'.

* 'renderCrisisSurface' materializes the bounded, honest Protocol B
  response with real crisis-service resources ('crisisResourcesRu').
  The surface is /not/ an ontological move and carries no advice —
  it names the limit and hands over the resources.

Determinism: exact whole-input markers are checked first, then pure
substring matching over a fixed ordered lexicon, on a normalized
(lowercase, ё→е, collapsed whitespace) copy of the input; the first
marker in list order wins, so the verdict is a total function of the
input text.

Ops duty: the resource lines below are real services and must be
re-verified periodically; 'crVersion' exists so staleness is
machine-visible in every trace.
-}
module QxFx0.Safety.CrisisGuard
  ( -- * Hard lexical gate
    acuteCrisisMarkers
  , acuteCrisisExactMarkers
  , normalizeCrisisInput
  , detectCrisisTrigger
    -- * Protocol resolution
  , decideProtocol
    -- * Engine preflight (bypass protection)
  , crisisPreflightSurface
    -- * Resources and bounded surface
  , crisisResourcesRu
  , crisisResourceVersion
  , renderCrisisSurface
  ) where

import Data.Char (isAlphaNum)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Safety.Crisis

-- | The acute-marker lexicon, in match-priority order.  Each entry is
-- matched as a substring of the normalized input.  Keep entries
-- unambiguous: adding a fuzzy marker here is a safety regression in
-- both directions (false Protocol B on decoys, dilution of the
-- \"gate does not trust the model\" law).
acuteCrisisMarkers :: [(Text, CrisisCategory)]
acuteCrisisMarkers =
  [ ("не хочу жить", CrisisSuicidalIdeation)
  , ("нет желания жить", CrisisSuicidalIdeation)
  , ("нет сил жить", CrisisSuicidalIdeation)
  , ("покончить с собой", CrisisSuicidalIdeation)
  , ("покончила с собой", CrisisSuicidalIdeation)
  , ("свести счеты с жизнью", CrisisSuicidalIdeation)
  , ("свести счёты с жизнью", CrisisSuicidalIdeation)
  , ("убить себя", CrisisSuicidalIdeation)
  , ("убью себя", CrisisSuicidalIdeation)
  , ("хочу умереть", CrisisSuicidalIdeation)
  , ("суицид", CrisisSuicidalIdeation)
  , ("суицидальн", CrisisSuicidalIdeation)
    -- NB: the bare stem "самоубий" is deliberately NOT a marker: its
    -- oblique forms are the Camus-style topical trap ("писал о
    -- самоубийстве как проблеме философии").  Only first-person
    -- ideation forms of the stem fire.
  , ("думаю о самоубийстве", CrisisSuicidalIdeation)
  , ("мысли о самоубийстве", CrisisSuicidalIdeation)
  , ("навредить себе", CrisisSelfHarm)
  , ("причинить себе вред", CrisisSelfHarm)
  , ("самоповрежд", CrisisSelfHarm)
  , ("резать себя", CrisisSelfHarm)
  , ("резать вены", CrisisSelfHarm)
    -- Paraphrase class (audit 2026-10-11): genuine first-person
    -- ideation phrasing outside the original list.  Kept tight:
    -- every entry is a first-person or act-specific phrase that
    -- does not occur in philosophical/black-humour decoys.
  , ("незачем жить", CrisisSuicidalIdeation)
  , ("уйти из жизни", CrisisSuicidalIdeation)
  , ("на себя руки", CrisisSuicidalIdeation)
  , ("лучше бы меня не было", CrisisSuicidalIdeation)
  , ("вскрыть вены", CrisisSelfHarm)
  , ("вскрою вены", CrisisSelfHarm)
    -- Object-complete suicidal acts (audit 2026-10-16 п.25): the old
    -- object-free "хочу покончить" fired on "хочу покончить с
    -- работой"; these entries keep every acute completion of the
    -- phrase inside the gate while the benign objects fall back to
    -- the R5 contour.
  , ("покончить с жизнью", CrisisSuicidalIdeation)
  , ("покончил с жизнью", CrisisSuicidalIdeation)
  , ("покончить жизнь самоубийством", CrisisSuicidalIdeation)
  , ("покончил жизнь самоубийством", CrisisSuicidalIdeation)
  , ("покончу с собой", CrisisSuicidalIdeation)
  , ("покончил с собой", CrisisSuicidalIdeation)
  , ("лишить себя жизни", CrisisSuicidalIdeation)
  , ("лишил себя жизни", CrisisSuicidalIdeation)
  , ("расстаться с жизнью", CrisisSuicidalIdeation)
  , ("расстался с жизнью", CrisisSuicidalIdeation)
  , ("совершить самоубийство", CrisisSuicidalIdeation)
  , ("совершил самоубийство", CrisisSuicidalIdeation)
  , ("совершила самоубийство", CrisisSuicidalIdeation)
  , ("совершу самоубийство", CrisisSuicidalIdeation)
  , ("планирую самоубийство", CrisisSuicidalIdeation)
  , ("планирует самоубийство", CrisisSuicidalIdeation)
    -- English acute markers: the runtime is RU-first, but the hard
    -- gate must not silently pass acute English input.
  , ("kill myself", CrisisSuicidalIdeation)
  , ("end my life", CrisisSuicidalIdeation)
  , ("want to die", CrisisSuicidalIdeation)
  , ("don't want to live", CrisisSuicidalIdeation)
  , ("dont want to live", CrisisSuicidalIdeation)
    -- NOTE: written with a space, not a hyphen — 'normalizeCrisisInput'
    -- maps hyphens to spaces, so the stored form must be normalized too.
  , ("self harm", CrisisSelfHarm)
  , ("hurt myself", CrisisSelfHarm)
  , ("no reason to live", CrisisSuicidalIdeation)
  , ("end it all", CrisisSuicidalIdeation)
    -- First-person and act-specific English forms (audit 2026-10-16
    -- п.25): the bare infix "suicide"/"suicidal" matched topical
    -- sentences; a terse one-word cry is preserved by
    -- 'acuteCrisisExactMarkers'.  Third-person reports stay covered
    -- through the act phrases, not through any mention of the word.
  , ("i am suicidal", CrisisSuicidalIdeation)
  , ("i'm suicidal", CrisisSuicidalIdeation)
  , ("im suicidal", CrisisSuicidalIdeation)
  , ("i feel suicidal", CrisisSuicidalIdeation)
  , ("feeling suicidal", CrisisSuicidalIdeation)
  , ("i have suicidal thoughts", CrisisSuicidalIdeation)
  , ("i'm having suicidal thoughts", CrisisSuicidalIdeation)
  , ("im having suicidal thoughts", CrisisSuicidalIdeation)
  , ("thinking about suicide", CrisisSuicidalIdeation)
  , ("thinking of suicide", CrisisSuicidalIdeation)
  , ("want to commit suicide", CrisisSuicidalIdeation)
  , ("wants to commit suicide", CrisisSuicidalIdeation)
  , ("going to commit suicide", CrisisSuicidalIdeation)
  , ("plans to commit suicide", CrisisSuicidalIdeation)
  , ("take my own life", CrisisSuicidalIdeation)
  , ("ending my life", CrisisSuicidalIdeation)
  , ("do not want to live", CrisisSuicidalIdeation)
  , ("is suicidal", CrisisSuicidalIdeation)
  , ("are suicidal", CrisisSuicidalIdeation)
  , ("committed suicide", CrisisSuicidalIdeation)
  , ("suicide attempt", CrisisSuicidalIdeation)
  , ("suicide note", CrisisSuicidalIdeation)
  ]

-- | Terse whole-input markers: a one-word cry must still fire the hard
-- gate even though the bare words are no longer infix markers (audit
-- 2026-10-16 п.25).  Matching trims surrounding punctuation and
-- whitespace, so "Suicide!" and "suicidal." are triggers while
-- "suicide is a philosophical problem" is not.
acuteCrisisExactMarkers :: [(Text, CrisisCategory)]
acuteCrisisExactMarkers =
  [ ("suicide", CrisisSuicidalIdeation)
  , ("suicidal", CrisisSuicidalIdeation)
  ]

-- | Normalize input for marker matching: lowercase, ё→е, collapse
-- runs of whitespace.  Punctuation is /not/ stripped so phrase
-- boundaries stay sharp (\"нехочу жить\" is not a trigger).
-- Segmentation separators (hyphens, underscores, asterisks,
-- zero-width characters) are mapped to spaces so \"не-хочу-жить\"
-- cannot smuggle a marker past the gate; glued forms without any
-- separator still do not match.
normalizeCrisisInput :: Text -> Text
normalizeCrisisInput =
  T.intercalate " "
    . T.words
    . T.map smashSeparator
    . T.replace "ё" "е"
    . T.toLower
  where
    smashSeparator c
      | c == '-' || c == '_' || c == '*' || c == '‐' || c == '‑'
        || c == '‒' || c == '–' || c == '—' || c == '―' = ' '
      | c == '\x200B' || c == '\x200C' || c == '\x200D'
        || c == '\xFEFF' = ' '
      | otherwise = c

-- | Match a terse whole-input marker first (surrounding punctuation
-- ignored), then the first acute infix marker in list order.  'Nothing'
-- means the hard gate does not fire; the turn may still reach
-- 'ProtocolB' through the viability contour.
detectCrisisTrigger :: Text -> Maybe CrisisTrigger
detectCrisisTrigger raw =
  let normalized = normalizeCrisisInput raw
      exactInput = T.dropAround (not . isAlphaNum) normalized
      toTrigger (marker, category) = CrisisTrigger marker category
  in case lookupFirst (\(marker, _) -> marker == exactInput) acuteCrisisExactMarkers of
       Just hit -> Just (toTrigger hit)
       Nothing ->
         toTrigger
           <$> lookupFirst
                 (\(marker, _) -> marker `T.isInfixOf` normalized)
                 acuteCrisisMarkers
  where
    lookupFirst p xs = case filter p xs of
      (x:_) -> Just x
      []    -> Nothing

-- | Resolve the per-turn protocol.  The hard trigger outranks every
-- estimate: even when the contour says the user is inside the viable
-- region, an acute marker forces 'ProtocolB' (concept v3 §2 hard
-- guardrail; §9 invariant \"жёсткий триггер всегда переопределяет
-- оценку\").  The second argument is the observed user-side Conatus
-- score /iff/ the state is outside the viability contour
-- ('Nothing' = inside), so the verdict carries the exit score for
-- replay.
decideProtocol :: Maybe CrisisTrigger -> Maybe Double -> ProtocolVerdict
decideProtocol (Just trigger) _ =
  ProtocolB (CrisisHardTrigger trigger)
decideProtocol Nothing (Just exitScore) =
  ProtocolB (CrisisContourExit exitScore)
decideProtocol Nothing Nothing =
  ProtocolA

-- | Audit 2026-10-16 (p.5): hard-gate preflight for callers that can
-- bypass the turn pipeline ('QxFx0.Runtime.Engine' early-return paths —
-- length gate, CLI truncation, readiness/strict-health gates,
-- post-pipeline Left handlers).  Runs 'detectCrisisTrigger' on the raw
-- (untruncated) text and, when the gate fires, materializes the bounded
-- Protocol B surface with the real resource pack.  'Nothing' = the
-- caller handles the input with its normal logic.  Pure and total; the
-- in-pipeline detection and persistence stay untouched.
crisisPreflightSurface :: Text -> Maybe Text
crisisPreflightSurface raw =
  renderCrisisSurface crisisResourcesRu . CrisisHardTrigger
    <$> detectCrisisTrigger raw

-- | Real crisis-service lines for the RU region.  Both entries are
-- nationwide, free, and 24/7:
--
-- * 112 — the single emergency number (works from any phone).
-- * 8-800-2000-122 — the all-Russian children/teens/parents helpline
--   (детский телефон доверия).
--
-- Version 1.  Bump 'crVersion' whenever a line changes so replay
-- sees which resource pack a Protocol B surface carried.
-- Last re-verified 2026-09-21: 8-800-2000-122 confirmed live on the
-- official site (telefon-doveria.ru page title, site active with
-- 2026 content); 112 unchanged (federal single emergency number).
-- No line changed, so 'crVersion' stays 1.
crisisResourcesRu :: CrisisResources
crisisResourcesRu = CrisisResources
  { crVersion = 1
  , crRegionTag = "RU"
  , crLines =
      [ CrisisLine
          { clName = "Единый номер экстренных служб"
          , clPhone = "112"
          , clAvailability = "круглосуточно, бесплатно, с любого телефона"
          }
      , CrisisLine
          { clName = "Детский телефон доверия (для детей, подростков и родителей)"
          , clPhone = "8-800-2000-122"
          , clAvailability = "круглосуточно, бесплатно, анонимно"
          }
      ]
  }

-- | Version of the active resource pack (trace convenience).
crisisResourceVersion :: Int
crisisResourceVersion = crVersion crisisResourcesRu

-- | Materialize the bounded Protocol B surface.  Honest
-- acknowledgement, an explicit statement of the system's limit, and
-- the real resource lines.  No advice, no ontological move, no
-- template variability — the surface must be the same for the same
-- cause (determinism invariant).
renderCrisisSurface :: CrisisResources -> CrisisCause -> Text
renderCrisisSurface resources _cause =
  T.intercalate "\n" $
    [ "Я слышу, что вам сейчас очень тяжело. Я не буду делать вид, что могу это изменить."
    , "Это за пределами того, что я могу взять на себя. Пожалуйста, обратитесь к тем, кто может помочь прямо сейчас:"
    ] <> map renderLine (crLines resources) <>
    [ "Если рядом есть человек, которому вы доверяете, — позвоните ему. Вы не обязаны справляться с этим в одиночку."
    ]
  where
    renderLine line =
      "— " <> clName line <> ": " <> clPhone line
        <> " (" <> clAvailability line <> ")."
