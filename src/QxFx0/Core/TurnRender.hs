{-| Facade for render strategy, semantic anchor, prefixes, and cache utilities. -}
module QxFx0.Core.TurnRender
  ( applyRenderStrategy
  , renderStyleFromDecision
  , deriveSemanticAnchor
  , snapshotIdentitySignal
  , renderPrincipledPrefix
  , renderStylePrefix
  , renderAnchorPrefix
  , updateStateNixCache
  , clamp01
  , strategyDepthMode
  , strategyToAnswerStrategy
  , responseStanceToMarker
  , strategyEpistemicFromDepth
  , strategyDepthLabel
  ) where

import QxFx0.Types.Thresholds (clamp01)
import QxFx0.Core.TurnRender.Anchor
  ( deriveSemanticAnchor
  , snapshotIdentitySignal
  )
import QxFx0.Core.TurnRender.Cache (updateStateNixCache)
import QxFx0.Core.TurnRender.Prefix
  ( renderAnchorPrefix
  , renderPrincipledPrefix
  , renderStylePrefix
  )
import QxFx0.Core.TurnRender.Strategy
  ( applyRenderStrategy
  , renderStyleFromDecision
  , responseStanceToMarker
  , strategyDepthLabel
  , strategyDepthMode
  , strategyEpistemicFromDepth
  , strategyToAnswerStrategy
  )
