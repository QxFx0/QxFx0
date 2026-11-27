{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Internal.WireCompat
Description : internal — historical wire names kept stable across the P4 rename.

The 2026-11-23 P4 rename changed Haskell identifiers from @Conatus@ to
@StateIntegrity@.  Persisted stores and replay traces must keep decoding:
their JSON keys and constructor tags are a wire format, not a Haskell
detail.  Hand-written 'Data.Aeson' instances use 'legacyConatusLabel' to
map the new name back to the historical one on both encode and decode.

This module is deliberately tiny and has no dependencies beyond
@base@.  It is /not/ a general compatibility layer.
-}
module QxFx0.Internal.WireCompat
  ( legacyConatusLabel
  ) where

import Data.List (stripPrefix)

-- | Rewrite @StateIntegrity@ \/ @stateIntegrity@ back to
-- @Conatus@ \/ @conatus@.  Every other character is copied verbatim.
--
-- >>> legacyConatusLabel "DrivenByStateIntegrityGate"
-- "DrivenByConatusGate"
legacyConatusLabel :: String -> String
legacyConatusLabel [] = []
legacyConatusLabel s@(c:cs)
  | Just rest <- stripPrefix "StateIntegrity" s = "Conatus" ++ legacyConatusLabel rest
  | Just rest <- stripPrefix "stateIntegrity" s = "conatus" ++ legacyConatusLabel rest
  | otherwise = c : legacyConatusLabel cs
