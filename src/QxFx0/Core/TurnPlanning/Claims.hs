{-# LANGUAGE StrictData #-}

{-| Identity-claim integration and confidence filtering for planning context. -}
module QxFx0.Core.TurnPlanning.Claims
  ( integrateIdentityClaims
  ) where

import Data.Text (Text)

import QxFx0.Core.ClaimBuilder (deduplicateClaims, scoreClaims, selectTopClaims)
import QxFx0.Types
import QxFx0.Types.Thresholds (minIdentityClaimConfidence)

integrateIdentityClaims :: [IdentityClaimRef] -> CanonicalMoveFamily -> Text -> [IdentityClaimRef]
integrateIdentityClaims claims _family topic =
  let scored = scoreClaims claims topic
      topClaims = selectTopClaims 5 scored
      deduped = deduplicateClaims topClaims
   in filter (\claim -> icrConfidence claim >= minIdentityClaimConfidence) deduped
