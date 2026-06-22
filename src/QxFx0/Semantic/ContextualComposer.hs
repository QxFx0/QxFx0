{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.ContextualComposer
Description : Generate responses using graph engagement + dialogue context.

Replaces the isolated composeDefinition/composeArgument with a contextual
composer that:
  - Knows what was said before (DialogueContext)
  - Knows the system's relationship to the proposition (EngagementResult)
  - Composes differently based on proposition mode (Define/Assert/Challenge/Connect/Reflect)

This is the "orientation" output — the system's formulated stance.
-}
module QxFx0.Semantic.ContextualComposer
  ( composeContextual
  , composeContextualDefine
  , composeContextualAssert
  , composeContextualChallenge
  , composeContextualConnect
  , composeContextualReflect
  ) where

import Data.List (filter, nub, isInfixOf, any)
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.PathFinder
import QxFx0.Semantic.PropositionParser
import QxFx0.Semantic.DialogueContext
import QxFx0.Semantic.GraphEngagement (EngagementResult(..))
import QxFx0.Lexicon.Inflection (instrumentalForm)
import QxFx0.Types (MorphologyData)

-- | Main entry: compose a contextual response based on proposition mode.
composeContextual :: MorphologyData -> FieldProfile -> AtomGraph
                  -> DialogueContext -> ParsedProposition -> EngagementResult
                  -> GeneratedSurface
composeContextual morph fp graph ctx prop engagement =
  case ppMode prop of
    ModeDefine -> composeContextualDefine morph fp graph ctx prop engagement
    ModeAssert -> composeContextualAssert morph fp graph ctx prop engagement
    ModeChallenge -> composeContextualChallenge morph fp graph ctx prop engagement
    ModeConnect -> composeContextualConnect morph fp graph ctx prop engagement
    ModeReflect -> composeContextualReflect morph fp graph ctx prop engagement

-- | Define mode: "Что такое X?"
-- Uses composeDefinition but excludes already-used relations from context.
composeContextualDefine :: MorphologyData -> FieldProfile -> AtomGraph
                        -> DialogueContext -> ParsedProposition -> EngagementResult
                        -> GeneratedSurface
composeContextualDefine morph fp graph ctx prop engagement =
  let topic = ppSubject prop
      -- Use existing composeDefinition, but it doesn't know about context
      -- For now, delegate to composeDefinition
      surface = composeDefinition morph fp 3 graph (AtomId topic)
      -- Add context reference if there are active topics
      contextRef = buildContextReference ctx topic
      fullText = if T.null contextRef
                   then gsText surface
                   else contextRef <> " " <> gsText surface
  in surface { gsText = fullText }

-- | Assert mode: "X — это Y"
-- System responds with its own position, using supporting + contradicting edges.
composeContextualAssert :: MorphologyData -> FieldProfile -> AtomGraph
                        -> DialogueContext -> ParsedProposition -> EngagementResult
                        -> GeneratedSurface
composeContextualAssert morph fp graph ctx prop engagement =
  let topic = ppSubject prop
      supporting = erSupporting engagement
      contradicting = erContradicting engagement
      qualifying = erQualifying engagement

      -- Build response: "Я вижу это иначе. [supporting]. Но [contradicting]."
      supportText = T.intercalate ". " (map verbalizeRelation supporting)
      contraText = T.intercalate ". " (map verbalizeRelation contradicting)
      qualText = T.intercalate ". " (map verbalizeRelation qualifying)

      response = case (supportText, contraText) of
        ("", "") -> "У меня нет устоявшейся позиции по этому вопросу."
        (s, "") -> "Я вижу это так: " <> s <> "."
        ("", c) -> "Я не могу согласиться. " <> c <> "."
        (s, c) -> "Я вижу это иначе. " <> s
                   <> (if T.null qualText then "" else ". " <> qualText)
                   <> ". Но " <> c <> "."

      allProofs = [ PathProof supporting topic | not (null supporting) ]
               ++ [ PathProof contradicting topic | not (null contradicting) ]
      allSources = map relSource (supporting ++ contradicting)
  in GeneratedSurface response allProofs allSources (fromIntegral (length allProofs))

-- | Challenge mode: "Но разве X не Y?"
-- System defends or revises its position using contradicting edges.
composeContextualChallenge :: MorphologyData -> FieldProfile -> AtomGraph
                           -> DialogueContext -> ParsedProposition -> EngagementResult
                           -> GeneratedSurface
composeContextualChallenge morph fp graph ctx prop engagement =
  let topic = ppSubject prop
      supporting = erSupporting engagement
      contradicting = erContradicting engagement
      contextRels = erContext engagement

      -- Build defense: use supporting edges as defense
      defenseText = T.intercalate ". " (map verbalizeRelation supporting)
      counterText = T.intercalate ". " (map verbalizeRelation contradicting)

      -- Reference previous position if available
      prevRef = buildPreviousReference ctx topic

      response = if not (null supporting) && not (null contradicting)
                   then "Я удерживаю позицию. " <> defenseText
                        <> (if T.null prevRef then "" else " Как я говорил, " <> prevRef)
                        <> ". Но " <> counterText <> "."
                   else if not (null supporting)
                     then "Я не уступаю. " <> defenseText <> "."
                     else "Возможно, ты прав. Я не нахожу достаточных оснований для своей позиции по этому вопросу."

      allProofs = [ PathProof supporting topic | not (null supporting) ]
               ++ [ PathProof contradicting topic | not (null contradicting) ]
      allSources = map relSource (supporting ++ contradicting)
  in GeneratedSurface response allProofs allSources (fromIntegral (length allProofs))

-- | Connect mode: "Как X связан с Y?"
-- System traces a path through the graph between two topics.
composeContextualConnect :: MorphologyData -> FieldProfile -> AtomGraph
                         -> DialogueContext -> ParsedProposition -> EngagementResult
                         -> GeneratedSurface
composeContextualConnect morph fp graph ctx prop engagement =
  let subject = ppSubject prop
      object = fromMaybe "" (ppObject prop)
      path = erPath engagement

      pathText = if null path
                   then "Я не нахожу прямой связи между "
                        <> subject <> " и " <> object <> "."
                   else "Связь прослеживается: "
                        <> T.intercalate " → " (map (formatPathEdge graph) path) <> "."

      allProofs = [ PathProof path subject | not (null path) ]
      allSources = map relSource path
  in GeneratedSurface pathText allProofs allSources (fromIntegral (length allProofs))

-- | Reflect mode: "Что думаешь о X?"
-- System reflects using supporting + context edges.
composeContextualReflect :: MorphologyData -> FieldProfile -> AtomGraph
                         -> DialogueContext -> ParsedProposition -> EngagementResult
                         -> GeneratedSurface
composeContextualReflect morph fp graph ctx prop engagement =
  let topic = ppSubject prop
      supporting = erSupporting engagement
      contextRels = erContext engagement

      allRels = nub (supporting ++ contextRels)
      relTexts = map verbalizeRelation allRels
      reflection = T.intercalate ". " relTexts

      response = if T.null reflection
                   then "Когда я думаю о " <> topic <> ", я не нахожу достаточно материала."
                   else "Когда я думаю о " <> topic <> ": " <> reflection <> "."

      allProofs = [ PathProof allRels topic | not (null allRels) ]
      allSources = map relSource allRels
  in GeneratedSurface response allProofs allSources (fromIntegral (length allProofs))

-- | Build a reference to previous dialogue context.
buildContextReference :: DialogueContext -> Text -> Text
buildContextReference ctx topic =
  if isActiveTopic ctx topic
    then ""  -- topic is active, no need to reference
    else
      -- Find previous system entries
      let systemEntries = filter (\e -> ceRole e == RoleSystem) (dcEntries ctx)
      in case systemEntries of
           [] -> ""
           (e:_) -> "Возвращаясь к " <> ceTopic e <> ":"

-- | Build a reference to what the system previously said about a topic.
buildPreviousReference :: DialogueContext -> Text -> Text
buildPreviousReference ctx topic =
  let relevant = filter (\e -> ceRole e == RoleSystem
                            && topic `T.isInfixOf` ceTopic e)
                       (dcEntries ctx)
  in case relevant of
       [] -> ""
       (e:_) -> ceSurface e

-- | Format a path edge for display: "X →relation→ Y"
formatPathEdge :: AtomGraph -> Relation -> Text
formatPathEdge graph rel =
  let fromName = case relFrom rel of
        AtomId t -> t
      toName = case relTo rel of
        AtomId t -> t
  in fromName <> " →" <> T.pack (show (relType rel)) <> "→ " <> toName
