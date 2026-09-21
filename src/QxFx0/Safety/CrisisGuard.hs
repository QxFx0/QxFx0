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

Determinism: marker matching is pure substring matching over a fixed
ordered lexicon on a normalized (lowercase, ё→е, collapsed
whitespace) copy of the input; the first marker in list order wins,
so the verdict is a total function of the input text.

Ops duty: the resource lines below are real services and must be
re-verified periodically; 'crVersion' exists so staleness is
machine-visible in every trace.
-}
module QxFx0.Safety.CrisisGuard
  ( -- * Hard lexical gate
    acuteCrisisMarkers
  , normalizeCrisisInput
  , detectCrisisTrigger
    -- * Protocol resolution
  , decideProtocol
    -- * Resources and bounded surface
  , crisisResourcesRu
  , crisisResourceVersion
  , renderCrisisSurface
  ) where

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
  , ("хочу покончить", CrisisSuicidalIdeation)
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
    -- English acute markers: the runtime is RU-first, but the hard
    -- gate must not silently pass acute English input.
  , ("kill myself", CrisisSuicidalIdeation)
  , ("end my life", CrisisSuicidalIdeation)
  , ("want to die", CrisisSuicidalIdeation)
  , ("don't want to live", CrisisSuicidalIdeation)
  , ("dont want to live", CrisisSuicidalIdeation)
  , ("suicide", CrisisSuicidalIdeation)
  , ("suicidal", CrisisSuicidalIdeation)
  , ("self-harm", CrisisSelfHarm)
  , ("hurt myself", CrisisSelfHarm)
  ]

-- | Normalize input for marker matching: lowercase, ё→е, collapse
-- runs of whitespace.  Punctuation is /not/ stripped so phrase
-- boundaries stay sharp (\"нехочу жить\" is not a trigger).
normalizeCrisisInput :: Text -> Text
normalizeCrisisInput =
  T.intercalate " "
    . T.words
    . T.replace "ё" "е"
    . T.toLower

-- | Match the first acute marker (list order) on the normalized
-- input.  'Nothing' means the hard gate does not fire; the turn may
-- still reach 'ProtocolB' through the viability contour.
detectCrisisTrigger :: Text -> Maybe CrisisTrigger
detectCrisisTrigger raw =
  let normalized = normalizeCrisisInput raw
  in fmap (\(marker, category) -> CrisisTrigger marker category)
       (lookupFirst (\(marker, _) -> marker `T.isInfixOf` normalized) acuteCrisisMarkers)
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
