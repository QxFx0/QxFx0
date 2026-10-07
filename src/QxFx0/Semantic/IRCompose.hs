{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.IRCompose
Description : canonical — typed semantic composition with entailment boundaries.

Status (2026-10-07, Stage-1 Batch C, ADR-0054): SHADOW ONLY.
Nothing in the runtime calls this module. Composition compiles
DOWN to strict rules, so Batch A verdicts apply unchanged:
inherited consequences flow, blocked ones are never emitted
(enforced at expansion, not by post-filter).

A composition refines base rules with extra premises, adds new
conclusions, and withholds blocked conclusions. Role
compatibility (no dangling variables), scope preservation
(quantifier/modal wrappers carried intact) and conflict
propagation (via 'detectConflict' on the expansion) are
checked at expansion time. Total: every function terminates;
failures are data errors ('Left'), never exceptions.
-}
module QxFx0.Semantic.IRCompose
  ( CompositionDef(..)
  , expandComposition
  , expansionConflicts
  ) where

import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.IR
  ( Proposition(..)
  , freeVariables
  )
import QxFx0.Semantic.IREval
  ( StrictRule(..)
  , detectConflict
  )

-- | A composite concept: base rules refined with extra premises,
-- new conclusions added, and blocked conclusions withheld even
-- when a base rule would derive them.
data CompositionDef = CompositionDef
  { cdId :: !Text
  , cdBases :: ![StrictRule]
  , cdExtraPremises :: ![Proposition]
  , cdAddedConclusions :: ![Proposition]
  , cdBlocked :: ![Proposition]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Expand a composition into strict rules. Fails on role
-- incompatibility: every free variable in the additions must be
-- bound by some base premise (no dangling variables). Scope is
-- preserved structurally: premises (including quantifier/modal
-- wrappers) are carried intact, never stripped or flattened.
expandComposition :: CompositionDef -> Either String [StrictRule]
expandComposition def = do
  checkRoles
  pure (refinedBases ++ addedRules)
  where
    boundVars =
      S.unions (map (freeVariables . And . srPremises) (cdBases def))
    newVars =
      S.unions (map freeVariables (cdExtraPremises def))
        `S.union` S.unions (map freeVariables (cdAddedConclusions def))
    checkRoles =
      let dangling = newVars `S.difference` boundVars
      in if S.null dangling
           then Right ()
           else Left ("dangling variables in " <> show (cdId def)
                       <> ": " <> show (S.toList dangling))
    refinedBases =
      [ StrictRule (cdId def <> "#" <> srId base)
          (srPremises base ++ cdExtraPremises def)
          (srConclusion base)
      | base <- cdBases def
      , srConclusion base `notElem` cdBlocked def
      ]
    sharedPremises =
      concatMap srPremises (cdBases def) ++ cdExtraPremises def
    addedRules =
      [ StrictRule (cdId def <> "#add" <> T.pack (show i)) sharedPremises conclusion
      | (i, conclusion) <- zip [0 :: Int ..] (cdAddedConclusions def)
      , conclusion `notElem` cdBlocked def
      ]

-- | Conflict propagation: a base conflict with the additions
-- surfaces through 'detectConflict' over the expansion's
-- conclusions, never silently.
expansionConflicts :: [StrictRule] -> Maybe (Proposition, Proposition)
expansionConflicts rules =
  detectConflict (map srConclusion rules)
