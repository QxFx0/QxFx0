{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Tension delta estimation from lexical distress/negative markers. -}
module QxFx0.Core.TurnModulation.Tension
  ( computeTensionDelta
  ) where

import Data.Text (Text)

import QxFx0.Core.Policy.ParserKeywords
  ( tensionDistressKeywords
  , tensionNegativeKeywords
  )
import QxFx0.Core.Semantic.KeywordMatch
  ( containsAnyKeywordPhrase
  , tokenizeKeywordText
  )
import QxFx0.Types
import QxFx0.Types.Thresholds
  ( tensionDistressDelta
  , tensionEgoCarryFactor
  , tensionNegativeDelta
  )

computeTensionDelta :: Text -> SystemState -> Double
computeTensionDelta rawText systemState =
  let tokens = tokenizeKeywordText rawText
      hasNegative = containsAnyKeywordPhrase tokens tensionNegativeKeywords
      hasDistress = containsAnyKeywordPhrase tokens tensionDistressKeywords
      baseDelta =
        if hasNegative
          then tensionNegativeDelta
          else if hasDistress then tensionDistressDelta else 0.0
   in baseDelta + egoTension (ssEgo systemState) * tensionEgoCarryFactor
