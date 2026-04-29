{-# LANGUAGE StrictData #-}

{-| Rendering-side bounded cache updates for Nix guard outcomes. -}
module QxFx0.Core.TurnRender.Cache
  ( updateStateNixCache
  ) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)

import QxFx0.Types
import QxFx0.Types.Thresholds (nixCacheMaxSize)

updateStateNixCache :: Text -> NixGuardStatus -> Map.Map Text NixGuardStatus -> Map.Map Text NixGuardStatus
updateStateNixCache key status oldCache =
  let inserted = Map.insert key status oldCache
   in if Map.size inserted <= nixCacheMaxSize
        then inserted
        else Map.fromList (take nixCacheMaxSize (Map.toList inserted))
