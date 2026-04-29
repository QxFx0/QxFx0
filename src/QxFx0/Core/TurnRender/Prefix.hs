{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Render prefix builders for principled mode, style, and semantic anchors. -}
module QxFx0.Core.TurnRender.Prefix
  ( renderPrincipledPrefix
  , renderStylePrefix
  , renderAnchorPrefix
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.PrincipledCore
  ( PrincipledMode
  , PressureSignal
  , principledToPromptSection
  )
import QxFx0.Types
import QxFx0.Types.Thresholds (anchorStabilityThreshold)

renderPrincipledPrefix :: Maybe PressureSignal -> PrincipledMode -> Text
renderPrincipledPrefix pressure mode =
  case pressure of
    Nothing -> ""
    Just signal ->
      let firstLine = T.takeWhile (/= '\n') (principledToPromptSection signal mode)
       in if T.null firstLine then "" else firstLine

renderStylePrefix :: RenderStyle -> Text
renderStylePrefix StyleFormal = "Режим: формализация."
renderStylePrefix StyleWarm = "Режим: бережный контакт."
renderStylePrefix StyleDirect = "Режим: прямой вызов."
renderStylePrefix StylePoetic = "Режим: образная глубина."
renderStylePrefix StyleClinical = "Режим: клиническая точность."
renderStylePrefix StyleCautious = "Режим: осторожная формулировка."
renderStylePrefix StyleRecovery = "Режим: восстановление хода."
renderStylePrefix StyleStandard = ""

renderAnchorPrefix :: SemanticAnchor -> Text
renderAnchorPrefix anchor =
  if saStability anchor >= anchorStabilityThreshold
    then "Якорь: " <> dominantChannelText (saDominantChannel anchor)
    else ""
