{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.DialogueContext
Description : Multi-turn dialogue context for contextual composition.

Tracks the last N turns of dialogue to enable:
  - Deduplication: don't repeat already-used relations
  - Thematic continuity: prefer edges connected to active topics
  - Positional consistency: reference previously stated positions
  - User tracking: remember what the user asserted

Stored in SystemState.ssDialogue (via DialogueState).
TTL-based: entries decay after N turns of inactivity.
-}
module QxFx0.Semantic.DialogueContext
  ( DialogueContext(..)
  , ContextEntry(..)
  , ContextRole(..)
  , emptyContext
  , addSystemEntry
  , addUserEntry
  , pruneContext
  , isActiveTopic
  , isUsedRelation
  , getContextRelations
  , contextDepth
  ) where

import Data.List (nub, filter, isInfixOf, any)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Semantic.AtomGraph (Relation(..), relRuOriginal)
import QxFx0.Types.Semantic.DialogueContext
  ( DialogueContext(..)
  , ContextEntry(..)
  , ContextRole(..)
  , emptyDialogueContext
  )

-- | Empty context for session start.
emptyContext :: DialogueContext
emptyContext = emptyDialogueContext

-- | Add a system entry to the context.
addSystemEntry :: DialogueContext -> Text -> Text -> [Relation] -> DialogueContext
addSystemEntry ctx topic surface rels =
  let turn = dcTurnCount ctx + 1
      entry = ContextEntry
        { ceTurn = turn
        , ceRole = RoleSystem
        , ceTopic = topic
        , ceSurface = surface
        , ceRelations = rels
        , ceTTL = dcTTL ctx
        }
  in pruneContext $ ctx
       { dcEntries = dcEntries ctx ++ [entry]
       , dcTurnCount = turn
       }

-- | Add a user entry to the context.
addUserEntry :: DialogueContext -> Text -> Text -> DialogueContext
addUserEntry ctx topic input =
  let turn = dcTurnCount ctx + 1
      entry = ContextEntry
        { ceTurn = turn
        , ceRole = RoleUser
        , ceTopic = topic
        , ceSurface = input
        , ceRelations = []
        , ceTTL = dcTTL ctx
        }
  in pruneContext $ ctx
       { dcEntries = dcEntries ctx ++ [entry]
       , dcTurnCount = turn
       }

-- | Prune: decrement TTL, remove expired entries, cap at maxEntries.
pruneContext :: DialogueContext -> DialogueContext
pruneContext ctx =
  let -- Decrement TTL for all entries
      decremented = [ e { ceTTL = ceTTL e - 1 } | e <- dcEntries ctx ]
      -- Remove expired (TTL <= 0)
      alive = filter (\e -> ceTTL e > 0) decremented
      -- Cap at maxEntries (keep most recent)
      capped = if length alive > dcMaxEntries ctx
                 then drop (length alive - dcMaxEntries ctx) alive
                 else alive
  in ctx { dcEntries = capped }

-- | Check if a topic is active (mentioned in last 3 entries).
isActiveTopic :: DialogueContext -> Text -> Bool
isActiveTopic ctx topic =
  let recent = drop (max 0 (length (dcEntries ctx) - 3)) (dcEntries ctx)
  in any (\e -> topic `T.isInfixOf` ceTopic e || topic `T.isInfixOf` ceSurface e) recent

-- | Check if a relation was already used in context.
isUsedRelation :: DialogueContext -> Relation -> Bool
isUsedRelation ctx rel =
  let usedTexts = concatMap ceRelations (dcEntries ctx)
  in relRuOriginal rel `elem` map relRuOriginal usedTexts

-- | Get all relations from system entries in context.
getContextRelations :: DialogueContext -> [Relation]
getContextRelations ctx =
  nub $ concatMap ceRelations
      $ filter (\e -> ceRole e == RoleSystem)
      $ dcEntries ctx

-- | How deep is the context (how many system entries with relations).
contextDepth :: DialogueContext -> Int
contextDepth ctx =
  length $ filter (\e -> ceRole e == RoleSystem && not (null (ceRelations e)))
        $ dcEntries ctx
