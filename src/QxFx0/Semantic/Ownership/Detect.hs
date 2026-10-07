{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Ownership.Detect
Description : canonical — micro-grammar detectors for ownership events.

Status (2026-10-07, cutover Stage 1a, ADR-0055): COMPUTE-ONLY
wiring support. Total, pure, deterministic. Maps Russian
utterances to ownership-domain event candidates with explicit
participants, or closes the gate with a reason. Deliberately
boring: verb-stem sets are disjoint by construction; exactly
one event may match (ambiguity closes the gate); pronouns and
bare roles close the gate; fewer than two explicit mentions
closes the gate. Multi-turn histories need the session journal
(Stage 1b) and are not attempted here. Participant roles assume
canonical order (agent before recipient); case-based role
resolution is deferred work, documented not silent.
-}
module QxFx0.Semantic.Ownership.Detect
  ( OwnershipDetection(..)
  , GateReason(..)
  , detectOwnershipEvent
  , ownershipPronouns
  , isMentionEntity
  ) where

import Data.Text (Text)
import qualified Data.Text as T

-- | Why the gate did or did not fire.
data GateReason
  = GateFired
  | GateNoEventMatch
  | GateAmbiguousEvents ![Text]
  | GatePronounParticipant
  | GateMissingParties
  deriving stock (Eq, Show)

-- | A detected ownership event: the library event id plus
-- participant mentions in utterance order (agent first by
-- convention below) and the object mention.
data OwnershipDetection = OwnershipDetection
  { odEventId :: !Text
  , odAgent :: !Text
  , odRecipient :: !Text
  , odObject :: !Text
  } deriving stock (Eq, Show)

-- | A mention is entity-like when capitalized (proper name).
-- Used by the shadow-compare wiring to choose Entity vs Concept
-- terms; lowercase mentions become concepts.
isMentionEntity :: Text -> Bool
isMentionEntity w = case T.uncons w of
  Just (c, _) -> ('A' <= c && c <= 'Z') || ('\x0410' <= c && c <= '\x042F') || c == '\x0401'
  Nothing -> False

-- | Frozen Russian pronoun inventory (all cases, both numbers,
-- formal and informal). Any participant resolving to one of
-- these closes the gate: the IR path never guesses referents.
ownershipPronouns :: [Text]
ownershipPronouns =
  [ "я", "меня", "мне", "мной", "мною"
  , "ты", "тебя", "тебе", "тобой", "тобою"
  , "он", "его", "него", "ему", "нему", "им", "ним"
  , "она", "ее", "её", "нее", "неё", "ей", "ней", "ею", "нею"
  , "оно"
  , "мы", "нас", "нам", "нами"
  , "вы", "вас", "вам", "вами"
  , "они", "их", "них", "им", "ним", "ими", "ними"
  , "себя", "себе", "собой", "собою"
  ]

-- | Verb-stem sets per event, disjoint by construction.
-- Stems are matched as infixes on the lowered utterance.
eventStems :: [(Text, [Text])]
eventStems =
  [ ("give", ["подари", "подарен", "дарю", "дарит"])
  , ("lend", ["одолжи", "почитать", "попользоваться"])
  , ("return", ["верни", "вернул", "возвраща", "обратно"])
  , ("take", ["возьми", "взял", "взяла", "заберу", "забрал"])
  , ("show", ["покажи", "показал", "посмотри"])
  , ("steal", ["украл", "украла", "укради", "стащил"])
  , ("return-right", ["верни право", "возвращаю право", "право возвращается"])
  ]

-- | Detect an ownership event. Returns the detection plus the
-- gate verdict ('GateFired' or the closing reason).
detectOwnershipEvent :: Text -> (Maybe OwnershipDetection, GateReason)
detectOwnershipEvent rawText =
  let lowered = T.toLower rawText
      matched = [ eid | (eid, stems) <- eventStems
                      , any (`T.isInfixOf` lowered) stems ]
  in case matched of
    [] -> (Nothing, GateNoEventMatch)
    [eid] -> checkParties eid (tokenize lowered)
    eids -> (Nothing, GateAmbiguousEvents eids)
  where
    tokenize t = filter (not . T.null) (map cleanWord (T.words t))
    cleanWord = T.dropAround (\c -> not (isAlphaNum c) && c /= '-')
    isAlphaNum c = ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
      || ('\x0400' <= c && c <= '\x04FF') || ('0' <= c && c <= '9')
    checkParties eid toks =
      let caps = [ w | w <- T.words rawText
                     , let c = cleanWord w
                     , not (T.null c)
                     , isCapitalized c ]
      in case caps of
        (agent : recipient : _) ->
          if any (`elem` ownershipPronouns) (map T.toLower [agent, recipient])
            then (Nothing, GatePronounParticipant)
            else case findObject toks agent recipient of
              Nothing -> (Nothing, GateMissingParties)
              Just obj
                | T.toLower obj `elem` ownershipPronouns -> (Nothing, GatePronounParticipant)
                | otherwise -> (Just (OwnershipDetection eid agent recipient obj), GateFired)
        _ -> (Nothing, GateMissingParties)
    isCapitalized w = isMentionEntity w
    findObject toks agent recipient =
      let partySet = map T.toLower [agent, recipient]
          content = [ w | w <- toks
                        , T.length w >= 3
                        , T.toLower w `notElem` partySet
                        , T.toLower w `notElem` ownershipPronouns
                        , not (isVerbForm w) ]
      in case content of
        (obj : _) -> Just obj
        [] -> Nothing
    isVerbForm w = any (`T.isInfixOf` w) (concatMap snd eventStems)
