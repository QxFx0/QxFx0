{-# LANGUAGE OverloadedStrings #-}

-- | Total only over generated curated predicates and argued leaves. A plan
-- with an unmapped learned or legacy predicate is rejected so the caller can
-- retain its governed non-GF fallback rather than smuggling text into GF.
module QxFx0.Semantic.ResponsePlan.GF
  ( responsePlanToGfExpr
  , semanticPropositionToGfExpr
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Lexicon.Generated.SemanticSlots
  ( CuratedPredicateSlots(..)
  , lookupArguedLeafConstructor
  , lookupCuratedPredicateSlots
  )
import QxFx0.Types.Semantic.ResponsePlan
  ( ResponseSemanticPlan(..)
  , SemanticProposition(..)
  )

responsePlanToGfExpr :: ResponseSemanticPlan -> Either Text Text
responsePlanToGfExpr plan =
  case rspPropositions plan of
    [] -> Left "response_plan_without_propositions"
    first:rest -> do
      firstExpr <- semanticPropositionToGfExpr first
      restExprs <- traverse discoursePropositionToGfExpr rest
      pure ("MoveFromDiscourse (" <> foldl sequenceDiscourse ("DiscourseThesis (" <> firstExpr <> ")") restExprs <> ")")
  where
    sequenceDiscourse discourse next =
      "DiscourseSequence (" <> discourse <> ") (" <> next <> ")"

-- Top-level discourse constructors project the new information from typed
-- relational propositions. The complete proposition remains in the plan.
discoursePropositionToGfExpr :: SemanticProposition -> Either Text Text
discoursePropositionToGfExpr proposition =
  case proposition of
    PropositionContrast _ counter -> discourse "DiscourseCounterpoint" counter
    PropositionConditional _ conclusion -> discourse "DiscourseConsequence" conclusion
    PropositionQuestion inner -> discourse "DiscourseCheck" inner
    _ -> discourse "DiscourseStatement" proposition
  where
    discourse constructor inner = do
      innerExpr <- semanticPropositionToGfExpr inner
      pure (constructor <> " (" <> innerExpr <> ")")

semanticPropositionToGfExpr :: SemanticProposition -> Either Text Text
semanticPropositionToGfExpr proposition =
  case proposition of
    PropositionPredicate subject relation object -> do
      let source = predicateSurface subject relation object
      case lookupArguedLeaf subject relation object of
        Just constructor -> pure constructor
        Nothing -> do
          slots <- lookupSlots source
          pure
            ( "MkSemanticPredicate "
                <> cpsSubjectConstructor slots
                <> " "
                <> cpsRelationConstructor slots
                <> " "
                <> cpsObjectConstructor slots
            )
    PropositionConditional premise conclusion -> binary "PropositionConditional" premise conclusion
    PropositionConjunction left right -> binary "PropositionConjunction" left right
    PropositionContrast thesis counter -> binary "PropositionContrast" thesis counter
    PropositionQuestion inner -> unary "PropositionQuestion" inner
    PropositionQualification inner condition -> binary "PropositionQualification" inner condition
  where
    unary constructor inner = do
      innerExpr <- semanticPropositionToGfExpr inner
      pure (constructor <> " (" <> innerExpr <> ")")
    binary constructor left right = do
      leftExpr <- semanticPropositionToGfExpr left
      rightExpr <- semanticPropositionToGfExpr right
      pure (constructor <> " (" <> leftExpr <> ") (" <> rightExpr <> ")")

lookupSlots :: Text -> Either Text CuratedPredicateSlots
lookupSlots source =
  case lookupCuratedPredicateSlots source of
    Just slots -> Right slots
    Nothing -> Left ("unmapped_curated_predicate:" <> source)

-- Argued leaves are cataloged verbatim. They must not be reconstructed from
-- subject/relation/object fragments or normalized at runtime.
lookupArguedLeaf :: Text -> Text -> Text -> Maybe Text
lookupArguedLeaf subject relation object
  | T.null subject && T.null object = lookupArguedLeafConstructor relation
  | otherwise = Nothing

predicateSurface :: Text -> Text -> Text -> Text
predicateSurface subject relation object =
  T.unwords (filter (not . T.null) [T.strip subject, T.strip relation, T.strip object])
