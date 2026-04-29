{-# LANGUAGE OverloadedStrings #-}

{-| Comparison of Haskell and Datalog shadow verdicts into divergence signals. -}
module QxFx0.Bridge.Datalog.Compare
  ( compareShadowOutput
  ) where

import QxFx0.Types
  ( R5Verdict
  , r5Clause
  , r5Family
  , r5Force
  , r5Layer
  , r5Warranted
  )
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  )

compareShadowOutput :: R5Verdict -> R5Verdict -> ShadowDivergence
compareShadowOutput haskellVerdict datalogVerdict =
  let familyMismatch = r5Family haskellVerdict /= r5Family datalogVerdict
      forceMismatch = r5Force haskellVerdict /= r5Force datalogVerdict
      clauseMismatch = r5Clause haskellVerdict /= r5Clause datalogVerdict
      layerMismatch = r5Layer haskellVerdict /= r5Layer datalogVerdict
      warrantedMismatch = r5Warranted haskellVerdict /= r5Warranted datalogVerdict
      hasMismatch =
        or
          [ familyMismatch
          , forceMismatch
          , clauseMismatch
          , layerMismatch
          , warrantedMismatch
          ]
   in ShadowDivergence
        { sdKind = if hasMismatch then ShadowVerdictMismatch else ShadowNoDivergence
        , sdFamilyMismatch = familyMismatch
        , sdForceMismatch = forceMismatch
        , sdClauseMismatch = clauseMismatch
        , sdLayerMismatch = layerMismatch
        , sdWarrantedMismatch = warrantedMismatch
        }
