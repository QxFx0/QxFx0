{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Types
Description : canonical — Pure type definitions for the Self layer (SelfBlanket invariants).

This module defines the typed snapshot of a system's structural
self-identity: the Markov-blanket-style record whose simultaneous
preservation across operations defines "this system, persisting".

The types here are intentionally minimal in P1. The full P2+ design
will extend this with conatus-functional carriers and
adjunction-pair witnesses; for now we record only what is needed to
detect identity rupture under existing operations.

See @docs\/THEORY.md@ §4.1 and @docs\/adr\/0007-dual-mode-conatus.md@.
-}
module QxFx0.Self.Types
  ( SelfBlanket (..)
  , BlanketViolation (..)
  , renderBlanketViolation
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON, object, (.=))
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | A snapshot of the system's structural self-identity at a single
-- point in time. Together the fields here form the Markov blanket
-- distinguishing /this system/ from any other system that happens
-- to share state shape.
--
-- The blanket is computed from a 'QxFx0.Types.State.SystemState'
-- (see 'QxFx0.Self.Blanket.computeSelfBlanket') and is intended to
-- be checked at two transition points in the runtime:
--
-- * after session bootstrap (initial blanket must satisfy
--   'QxFx0.Self.Invariants.checkInitialBlanket'); and
-- * after each commit (previous and current blankets together must
--   satisfy 'QxFx0.Self.Invariants.checkBlanketTransition').
data SelfBlanket = SelfBlanket
  { sbSessionId           :: Text
    -- ^ Session identifier the blanket was taken under. Must remain
    -- stable for the lifetime of a single session: a session
    -- identity change without an explicit re-bootstrap is a
    -- categorical failure ('BlanketSessionChanged').
  , sbMorphologyTotalSize :: Int
    -- ^ Total entry count across all morphology dictionaries
    -- (prepositional + genitive + nominative + forms-by-surface).
    -- Must be strictly positive: a system without lexical material
    -- cannot produce dialogue and so is not /this system/
    -- ('BlanketEmptyMorphology').
  , sbIdentityClaimsCount :: Int
    -- ^ Number of identity claims attached to the session. Must be
    -- non-decreasing across commits: silent erasure of claims is a
    -- categorical failure ('BlanketIdentityErased'). The count
    -- /may/ legitimately grow as new claims are discovered, and
    -- /may/ legitimately start at zero on a fresh session.
  , sbTurnCount           :: Int
    -- ^ Current turn count. Must be non-decreasing across commits
    -- ('BlanketTurnRegressed'). A turn-count regression indicates
    -- either persistence corruption or recovery to a state strictly
    -- older than the committed state.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

instance ToJSON SelfBlanket where
  toJSON sb = object
    [ "sessionId"            .= sbSessionId sb
    , "morphologyTotalSize"  .= sbMorphologyTotalSize sb
    , "identityClaimsCount"  .= sbIdentityClaimsCount sb
    , "turnCount"            .= sbTurnCount sb
    ]

instance FromJSON SelfBlanket where
  parseJSON = Aeson.withObject "SelfBlanket" $ \o -> SelfBlanket
    <$> o Aeson..: "sessionId"
    <*> o Aeson..: "morphologyTotalSize"
    <*> o Aeson..: "identityClaimsCount"
    <*> o Aeson..: "turnCount"

-- | A categorical failure of structural self-identity. Each
-- constructor names a single invariant that may be violated; a
-- single transition may emit zero, one, or several violations.
--
-- Violations are /not/ recoverable runtime errors in the
-- 'QxFx0.ExceptionPolicy' sense. They indicate that the system
-- has ceased to be /this system/. The corresponding exception
-- is 'QxFx0.ExceptionPolicy.IdentityRupture'.
data BlanketViolation
  = BlanketEmptySession
    -- ^ The session identifier in the blanket is the empty string.
  | BlanketEmptyMorphology
    -- ^ The morphology dictionaries are collectively empty.
  | BlanketSessionChanged !Text !Text
    -- ^ Session identifier changed between blankets:
    -- @BlanketSessionChanged previousSessionId currentSessionId@.
  | BlanketTurnRegressed !Int !Int
    -- ^ Turn count went down:
    -- @BlanketTurnRegressed previousTurnCount currentTurnCount@
    -- where @currentTurnCount < previousTurnCount@.
  | BlanketIdentityErased !Int !Int
    -- ^ Identity-claim count decreased:
    -- @BlanketIdentityErased previousCount currentCount@ where
    -- @currentCount < previousCount@.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Render a violation to a human-readable diagnostic, suitable
-- for inclusion in 'QxFx0.ExceptionPolicy.IdentityRupture' payloads
-- and observability logs.
renderBlanketViolation :: BlanketViolation -> Text
renderBlanketViolation = \case
  BlanketEmptySession ->
    "self-blanket: session identifier is empty"
  BlanketEmptyMorphology ->
    "self-blanket: morphology dictionaries are empty"
  BlanketSessionChanged prev cur ->
    "self-blanket: session identifier changed (was=\""
      <> prev
      <> "\" now=\""
      <> cur
      <> "\")"
  BlanketTurnRegressed prev cur ->
    "self-blanket: turn count regressed (was="
      <> T.pack (show prev)
      <> " now="
      <> T.pack (show cur)
      <> ")"
  BlanketIdentityErased prev cur ->
    "self-blanket: identity claim count erased (was="
      <> T.pack (show prev)
      <> " now="
      <> T.pack (show cur)
      <> ")"
