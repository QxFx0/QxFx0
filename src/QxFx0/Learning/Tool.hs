{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Tool
Description : WP2 — External tool awareness and selection.

Defines typed profiles for external knowledge sources (LLM, human mentor,
local calibration script) and a pure selection function that maps a
'LearningNeed' to the most appropriate available tool based on domain
match and reliability weighting.

No runtime code is auto-patched by a tool; only validated config/rules
may be updated through the closed loop (WP4).
-}
module QxFx0.Learning.Tool
  ( ToolDomain(..)
  , ExternalTool(..)
  , selectTool
  , selectToolWithReliability
  , updateToolReliability
  , renderTool
  , defaultAvailableTools
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Learning.Need (LearningNeed(..))

-- | Domain of expertise an external tool can cover.
data ToolDomain
  = DomainSalience
    -- ^ Tool can provide salience-weight calibration data.
  | DomainKeyword
    -- ^ Tool can supply keyword / ontology coverage.
  | DomainLexicon
    -- ^ Tool can extend morphology or lexicon entries.
  | DomainGeneral
    -- ^ General-purpose reasoning (fallback, lower priority).
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Typed profile of an external knowledge source.
data ExternalTool = ExternalTool
  { etName        :: !Text
    -- ^ Human-readable identifier (e.g. "local-calibration-script").
  , etDomain      :: !ToolDomain
    -- ^ Primary domain this tool covers.
  , etReliability :: !Double
    -- ^ Historical reliability in [0, 1].  Higher = more trustworthy.
  , etValidatable :: !Bool
    -- ^ Whether outputs from this tool can be run through the
    --   verify→simulate gate (WP4).  Non-validatable tools are
    --   rejected unless no validatable alternative exists.
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Map a 'LearningNeed' to the 'ToolDomain' it requires.
needDomain :: LearningNeed -> Maybe ToolDomain
needDomain NeedSalienceCalibration = Just DomainSalience
needDomain NeedKeywordEnrichment   = Just DomainKeyword
needDomain NeedLexiconExtension    = Just DomainLexicon
needDomain NeedNone                = Nothing

-- | Select the best external tool for a given 'LearningNeed'.
--
-- Rules:
-- 1. If 'NeedNone', no tool is selected.
-- 2. Filter tools whose domain matches the need.
-- 3. Prefer 'etValidatable = True'; if none, fall back to the
--    highest-reliability non-validatable tool.
-- 4. Among the candidate set, pick the one with highest
--    'etReliability'.  Ties are broken by declaration order
--    (stable, deterministic).
selectTool :: LearningNeed -> [ExternalTool] -> Maybe ExternalTool
selectTool need tools = do
  domain <- needDomain need
  let matching = filter ((== domain) . etDomain) tools
  if null matching
    then do
      -- Fallback: if no domain-specific tool, try DomainGeneral
      let general = filter ((== DomainGeneral) . etDomain) tools
      pickBest general
    else pickBest matching
  where
    pickBest candidates
      | null candidates = Nothing
      | otherwise       =
          let validatable = filter etValidatable candidates
              pool = if null validatable then candidates else validatable
          in maximumByReliability pool

    -- | Total: returns 'Nothing' only for an empty list.
    maximumByReliability :: [ExternalTool] -> Maybe ExternalTool
    maximumByReliability [] = Nothing
    maximumByReliability (x:xs) = Just (go x xs)
      where
        go best [] = best
        go best (y:ys)
          | etReliability y > etReliability best = go y ys
          | otherwise                            = go best ys

-- | WP5: variant of 'selectTool' that overlays dynamic reliability
-- from a runtime-maintained map.  If a tool's name is present in the
-- map, the map value overrides 'etReliability' for selection
-- purposes only; the static profile is not mutated.
selectToolWithReliability
  :: LearningNeed
  -> M.Map Text Double   -- ^ dynamic reliability overrides
  -> [ExternalTool]
  -> Maybe ExternalTool
selectToolWithReliability need relMap tools =
  let tools' = map (\t -> case M.lookup (etName t) relMap of
                            Just r  -> t { etReliability = clamp01 r }
                            Nothing -> t)
                 tools
  in selectTool need tools'
  where
    clamp01 x = max 0.0 (min 1.0 x)

-- | WP5: update tool reliability after an outcome.
--
-- * Acceptance → +0.05 (capped at 1.0)
-- * Rejection  → -0.10 (floored at 0.0)
--
-- These deltas are chosen so that 3 consecutive rejections drop a
-- perfectly reliable tool below 0.7, making it less attractive than
-- a fresh alternative.
updateToolReliability :: Text -> Bool -> M.Map Text Double -> M.Map Text Double
updateToolReliability toolName accepted relMap =
  let current = M.findWithDefault 0.5 toolName relMap
      delta = if accepted then 0.05 else (-0.10)
      updated = clamp01 (current + delta)
  in M.insert toolName updated relMap
  where
    clamp01 x = max 0.0 (min 1.0 x)

-- | Render an 'ExternalTool' to a short telemetry tag.
renderTool :: ExternalTool -> Text
renderTool t = T.concat
  [ etName t
  , "|domain="
  , renderDomain (etDomain t)
  , "|reliability="
  , T.pack (show (etReliability t))
  , "|validatable="
  , if etValidatable t then "1" else "0"
  ]

renderDomain :: ToolDomain -> Text
renderDomain DomainSalience = "salience"
renderDomain DomainKeyword    = "keyword"
renderDomain DomainLexicon    = "lexicon"
renderDomain DomainGeneral    = "general"

-- | Default set of external tools registered in the system.
-- These are static profiles; runtime does not mutate this list.
defaultAvailableTools :: [ExternalTool]
defaultAvailableTools =
  [ ExternalTool
      { etName        = "local-calibration-script"
      , etDomain      = DomainSalience
      , etReliability = 0.95
      , etValidatable = True
      }
  , ExternalTool
      { etName        = "human-mentor"
      , etDomain      = DomainKeyword
      , etReliability = 0.90
      , etValidatable = False
      }
  , ExternalTool
      { etName        = "llm-augment"
      , etDomain      = DomainLexicon
      , etReliability = 0.70
      , etValidatable = True
      }
  , ExternalTool
      { etName        = "llm-general"
      , etDomain      = DomainGeneral
      , etReliability = 0.60
      , etValidatable = False
      }
  ]
