{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Semantic anchor derivation and identity-signal snapshots for rendering. -}
module QxFx0.Core.TurnRender.Anchor
  ( deriveSemanticAnchor
  , snapshotIdentitySignal
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.IdentitySignal (IdentitySignal(..))
import QxFx0.Core.Semantic.SemanticInput (SemanticInput(..))
import QxFx0.Types
import QxFx0.Types.Thresholds
  ( clamp01
  , anchorNoTopicLowLoadThreshold
  , anchorCarryStabilityBaseline
  , anchorCarryStabilityStep
  , anchorResetStabilityDefault
  , anchorTopicPreviewChars
  )

deriveSemanticAnchor :: Maybe SemanticAnchor -> SemanticInput -> Text -> Int -> Maybe SemanticAnchor
deriveSemanticAnchor previous semanticInput topic turnNo
  | T.null (T.strip topic) && asLoad (siAtomSet semanticInput) < anchorNoTopicLowLoadThreshold = previous
  | otherwise =
      let channel = anchorChannel semanticInput
          previousChannel = fmap saDominantChannel previous
          sameChannel = previousChannel == Just channel
          establishedAt = if sameChannel then maybe turnNo saEstablishedAtTurn previous else turnNo
          strength = clamp01 (asLoad (siAtomSet semanticInput))
          stability =
            if sameChannel
              then clamp01 (maybe anchorCarryStabilityBaseline saStability previous + anchorCarryStabilityStep)
              else anchorResetStabilityDefault
       in Just SemanticAnchor
            { saDominantChannel = channel
            , saSecondaryChannel =
                if T.null topic
                  then Nothing
                  else Just (T.take anchorTopicPreviewChars topic)
            , saEstablishedAtTurn = establishedAt
            , saStrength = strength
            , saStability = stability
            }

snapshotIdentitySignal :: IdentitySignal -> IdentitySignalSnapshot
snapshotIdentitySignal signal =
  IdentitySignalSnapshot
    { issOrbitalPhase = isOrbitalPhase signal
    , issEncounterMode = isEncounterMode signal
    , issContactStrength = isContactStrength signal
    , issBoundaryStrength = isBoundaryStrength signal
    , issAbstractionBudget = isAbstractionBudget signal
    , issMoveBias = isMoveBias signal
    , issRegister = isRegister signal
    , issNeedLayer = isNeedLayer signal
    }

anchorChannel :: SemanticInput -> DominantChannel
anchorChannel semanticInput =
  case (siNeedLayer semanticInput, siRegister semanticInput, siRecommendedFamily semanticInput) of
    (ContactLayer, _, _) -> ChannelContact
    (_, Exhaust, _) -> ChannelRepair
    (_, Anchor, _) -> ChannelAnchor
    (_, Contact, _) -> ChannelContact
    (_, _, CMClarify) -> ChannelClarify
    (_, _, CMDefine) -> ChannelDefine
    (_, _, CMReflect) -> ChannelReflect
    _ -> ChannelGround
