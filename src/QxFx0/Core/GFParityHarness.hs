{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-|
Module      : QxFx0.Core.GFParityHarness
Description : M3.0 — GF relocation parity harness (reference table + verify).

Holds the reference table mapping each 'PropositionType' to its expected RU
surface text from the Haskell-template renderer.  Starts empty; entries are
captured and committed one type at a time during M3.1 as moves are migrated to
GF.  The 'verifyParity' function provides the mechanical gate @GF(move) ≡
reference@.

Inspired by the audit's "relocation, not generativity" decision (R-M3e): the
existing Haskell-template output IS the oracle.  Each GF migration proves it
reproduces the reference byte-for-byte before the Haskell fallback can be
retired (M3.2).

== Parity discipline

- Reference entries are append-only.  Changes are re-bless events gated by ADR
  + replay.
- Fully migrated moves keep their reference entry as a regression guard.
- The fixture used for capture is intentionally minimal (neutral frame, empty
  morphology) so the reference records the move's structural shape, not
  fixture-specific phrasing.
-}
module QxFx0.Core.GFParityHarness
  ( -- * Reference table
    ParityReference
  , emptyParityReference
  , lookupParityReference
  , insertParityReference
    -- * Verification
  , verifyParity
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Proposition.Types (PropositionType)

-- | The parity reference table: @PropositionType → expected RU surface text@.
-- Empty by construction; populated one type at a time during M3.1.
newtype ParityReference = ParityReference
  { unParityReference :: Map PropositionType Text
  } deriving stock (Eq, Show)

-- | An empty reference table (the initial state).
emptyParityReference :: ParityReference
emptyParityReference = ParityReference M.empty

-- | Look up the reference text for a proposition type.
lookupParityReference :: PropositionType -> ParityReference -> Maybe Text
lookupParityReference pt = M.lookup pt . unParityReference

-- | Add (or overwrite) a reference entry.  Overwrites are re-bless events and
-- should be gated by ADR + replay.
insertParityReference :: PropositionType -> Text -> ParityReference -> ParityReference
insertParityReference pt txt (ParityReference m) = ParityReference (M.insert pt txt m)

-- | Verify that a GF-produced text matches the Haskell-template reference.
-- Returns @Right ()@ on match, @Left msg@ with diagnostic on mismatch.
-- Types without a reference entry always pass (they haven't been captured yet).
verifyParity :: PropositionType -> Text -> ParityReference -> Either Text ()
verifyParity pt gfText ref =
  case lookupParityReference pt ref of
    Nothing     -> Right ()
    Just expect ->
      if T.strip gfText == T.strip expect
        then Right ()
        else Left $ T.unwords
          [ "GF PARITY FAIL [" <> T.pack (show pt) <> "]:"
          , "expected", T.take 80 expect <> "..."
          , "got", T.take 80 gfText <> "..."
          ]
