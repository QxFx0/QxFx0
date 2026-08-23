{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.Markers
Description : canonical — the single source of marker lexicons for the user-R5 encoder and the ontological classifier (audit P1-6).

Before this module the same words lived in three unsynchronized
lists with three different behavioural effects (\"надоело\" was
simultaneously a distress signal, an agency-negative signal, and a
striving-negative signal, each in its own copy).  This module is
the /only place* marker lexicons are defined for the concept-v3
regime; 'QxFx0.User.R5' and 'QxFx0.Semantic.Ontological' re-export
from here so existing imports keep working.

(*) 'QxFx0.Semantic.Intent.Features' keeps its own pre-existing
intent lexicons — folding those in is a separate, riskier change
(M4 classifier coupling) and stays out of scope here.

All lists are matched as substrings of a normalized (lowercase,
ё→е, collapsed whitespace) copy of the input; negative-before-
positive blanking is the caller's discipline (see 'User.R5' and
'Semantic.Ontological').  Lists are frozen v1 with the rest of the
regime; editing them is a 'currentMathVersion' bump.
-}
module QxFx0.Semantic.Markers
  ( -- * User-R5 encoder lexicons
    r5DistressMarkers
  , r5AgencyNegativeMarkers
  , r5AgencyPositiveMarkers
  , r5ResonanceAddressMarkers
  , r5ConsolidationMarkers
  , r5CounterfactualMarkers
    -- * Ontological-axis lexicons
  , beingPositiveMarkers
  , beingNegativeMarkers
  , strivingPositiveMarkers
  , strivingNegativeMarkers
  , affirmationPositiveMarkers
  , affirmationNegativeMarkers
  ) where

import Data.Text (Text)

-- | Tension/pressure signals for the user atmosphere axis.
r5DistressMarkers :: [Text]
r5DistressMarkers =
  [ "грустно", "тоскливо", "страшно", "тревожно", "плохо", "одиноко"
  , "устал", "устала", "больно", "тяжело", "бесит", "раздражает"
  , "не могу", "нет сил", "надоело", "выгорел", "выгорела"
  , "опустош", "отчаян", "безнадеж", "безнадёж", "бессмыслен"
  , "не выдерживаю", "не получается", "пусто", "давит"
  ]

-- | Agency-lowering phrases (confidence axis).  Blanked before the
-- positive list is counted.
r5AgencyNegativeMarkers :: [Text]
r5AgencyNegativeMarkers =
  [ "не хочу", "не буду", "не могу", "не смогу", "не получается"
  , "бесполезно", "безнадежно", "безнадёжно", "никогда не получится"
  , "надоело", "сдаюсь", "бросаю", "всё равно", "все равно"
  , "ничего не хочется", "не знаю зачем", "не выдерживаю", "нет сил"
  ]

-- | Agency-raising phrases (confidence axis).
r5AgencyPositiveMarkers :: [Text]
r5AgencyPositiveMarkers =
  [ "хочу", "могу", "смогу", "буду", "сделаю", "попробую", "выберу"
  , "стремлюсь", "ищу", "мечтаю", "намерен", "планирую", "решаю"
  ]

-- | Direct-address / engagement markers (resonance axis).
r5ResonanceAddressMarkers :: [Text]
r5ResonanceAddressMarkers =
  [ "ты можешь", "как ты", "а ты", "скажи", "ответь", "ты считаешь"
  , "ты думаешь", "по-твоему", "помоги мне понять"
  ]

-- | Causal/connective discourse markers (consolidation axis).
r5ConsolidationMarkers :: [Text]
r5ConsolidationMarkers =
  [ "потому что", "значит", "следовательно", "итак", "поэтому"
  , "связано", "исходя из", "отсюда", "таким образом"
  ]

-- | Alternative-opening markers (counterfactual axis).
r5CounterfactualMarkers :: [Text]
r5CounterfactualMarkers =
  [ "или", "может быть", "а если", "что если", "другой", "другие"
  , "иначе", "вариант", "предположим", "альтернатива", "с другой стороны"
  ]

-- | Affirmations of being (being axis, positive side).
beingPositiveMarkers :: [Text]
beingPositiveMarkers =
  [ "я есть", "я живу", "живу", "существует", "есть смысл"
  , "реально", "присутствует", "полноценно"
  ]

-- | Negations of being (being axis, negative side).
beingNegativeMarkers :: [Text]
beingNegativeMarkers =
  [ "нет смысла", "бессмыслен", "пусто", "ничто", "небытие"
  , "не существует", "исчез", "меня нет", "без меня"
  ]

-- | Striving (striving axis, positive side).
strivingPositiveMarkers :: [Text]
strivingPositiveMarkers =
  [ "хочу", "могу", "стремлюсь", "ищу", "выбираю", "мечтаю"
  , "попробую", "буду", "намерен", "сделаю"
  ]

-- | Denial of striving (striving axis, negative side).  Blanked
-- before the positive list is counted.
strivingNegativeMarkers :: [Text]
strivingNegativeMarkers =
  [ "не хочу", "не буду", "отказываюсь", "бросаю", "надоело"
  , "всё равно", "все равно", "сдаюсь", "не могу", "ничего не хочется"
  ]

-- | Building/affirming acts (affirmation axis, positive side).
affirmationPositiveMarkers :: [Text]
affirmationPositiveMarkers =
  [ "создаю", "строю", "утверждаю", "люблю", "поддерживаю"
  , "развиваю", "усиливаю", "берегу", "дорожу"
  ]

-- | Destroying acts (affirmation axis, negative side).
affirmationNegativeMarkers :: [Text]
affirmationNegativeMarkers =
  [ "разрушаю", "уничтож", "ломаю", "рушу", "ненавижу", "топчу"
  , "стираю", "сжигаю"
  ]
