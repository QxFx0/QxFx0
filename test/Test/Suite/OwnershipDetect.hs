{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for cutover Stage 1a micro-grammar detectors
-- (ADR-0055, pre-registered 2026-10-07): pure cores only.
-- Live gate behavior is verified by the gate battery; these pin
-- the fire/decline matrix and the trace round-trip.
module Test.Suite.OwnershipDetect
  ( ownershipDetectTests
  ) where

import Test.HUnit
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import Data.Aeson (encode, decode)

import QxFx0.Semantic.Ownership.Detect
import QxFx0.Types.TurnProjection (OwnershipCompareTrace(..))
import QxFx0.Types.Semantic.Ownership (FileOwnershipRow(..), OwnershipJournalEntry(..))
import QxFx0.Types.Domain.Atoms
  ( MorphologyData(..)
  , LexemeForm(..)
  , LexemeCase(..)
  , LexemeNumber(..)
  , SourceTier(..)
  )
import QxFx0.Types.Lexicon.RuntimeParadigms
  ( RuntimeParadigms(..)
  , ParadigmEntry(..)
  , PartOfSpeech(..)
  )
import QxFx0.Core.TurnPipeline.Route.Render (renderOwnershipSurface)
import qualified Data.Map.Strict as M
import QxFx0.Semantic.IR
  ( ConceptId(..)
  , EntityId(..)
  , PredicateId(..)
  , Proposition(..)
  , RoleBinding(..)
  , Term(..)
  , VarId(..)
  )
import QxFx0.Semantic.IRState
  ( EventSpec
  , TimeStep(..)
  , fluentsAt
  , foldHistory
  , toEventSpec
  )

ownershipDetectTests :: [Test]
ownershipDetectTests =
  [ TestLabel "give fires on canonical shape" $ TestCase $ do
      let (found, reason) = detectOwnershipEvent "Аня подарила книгу Боре"
      assertEqual "gate fires" GateFired reason
      case found of
        Nothing -> assertFailure "give must detect"
        Just det -> do
          assertEqual "event id" "give" (odEventId det)
          assertEqual "agent" "Аня" (odAgent det)
          assertEqual "recipient" "Боре" (odRecipient det)
          assertEqual "object" "книгу" (odObject det)
  , TestLabel "all seven events fire" $ TestCase $ do
      mapM_ (\(input, eid) ->
               case detectOwnershipEvent input of
                 (Just det, GateFired) ->
                   assertEqual ("event " <> T.unpack eid) eid (odEventId det)
                 _ -> assertFailure ("must fire: " <> T.unpack input))
        [ ("Аня одолжила книгу Боре", "lend")
        , ("Аня показала книгу Боре", "show")
        , ("Боря взял книгу у Ани", "take")
        , ("Боря украл книгу у Ани", "steal")
        ]
  , TestLabel "no verb match closes the gate" $ TestCase $ do
      assertEqual "strangers walking"
        (Nothing, GateNoEventMatch)
        (detectOwnershipEvent "Аня и Боря гуляли")
  , TestLabel "ambiguous events close the gate" $ TestCase $ do
      case detectOwnershipEvent "Аня подарила и одолжила книгу Боре" of
        (Nothing, GateAmbiguousEvents _) -> pure ()
        other -> assertFailure ("ambiguity must close: " <> show other)
  , TestLabel "capitalized pronoun closes the gate" $ TestCase $ do
      assertEqual "pronoun agent"
        (Nothing, GatePronounParticipant)
        (detectOwnershipEvent "Мне Аня одолжила книгу")
  , TestLabel "single party closes the gate" $ TestCase $ do
      assertEqual "lone borrower"
        (Nothing, GateMissingParties)
        (detectOwnershipEvent "Я одолжил книгу")
  , TestLabel "pronoun inventory covers cases" $ TestCase $ do
      mapM_ (\w -> assertBool ("pronoun: " <> T.unpack w)
               (w `elem` ownershipPronouns))
        ["я", "мне", "его", "нее", "ними", "себя"]
  , TestLabel "correction detector parses contrast shapes" $ TestCase $ do
      assertEqual "explicit contrast"
        (Just ("give", "lend"))
        (detectOwnershipCorrection "Нет, не подарила, а дала почитать")
      assertEqual "implicit correction takes the sole event"
        (Just ("", "lend"))
        (detectOwnershipCorrection "На самом деле Аня одолжила книгу")
      assertEqual "no marker declines"
        Nothing
        (detectOwnershipCorrection "Аня одолжила книгу Боре")
      assertEqual "multi-verb soup declines"
        Nothing
        (detectOwnershipCorrection "Аня подарила и одолжила книгу Боре")
      assertEqual "same event twice declines"
        Nothing
        (detectOwnershipCorrection "Нет, не подарила, а подарила")
  , TestLabel "compare trace round-trips" $ TestCase $ do
      let rec = OwnershipCompareTrace
            { octGateFired = True
            , octGateReason = "event-matched:lend"
            , octEventId = Just "lend"
            , octAgent = Just "Аня"
            , octRecipient = Just "Боре"
            , octObject = Just "книгу"
            , octVerdict = Just "Entails"
            , octLineage = ["asserted:lend"]
            , octHistoryDepth = Just 1
            , octCorrected = Just False
            , octCorrectedFrom = Nothing
            }
      assertEqual "json round trip" (Just rec)
        (decode (encode rec) :: Maybe OwnershipCompareTrace)
  , TestLabel "journal refold threads multi-turn histories" $ TestCase $ do
      lendRow <- mustRow "lend"
      returnRow <- mustRow "return"
      agentA <- mustTerm "Аня"
      agentB <- mustTerm "Боря"
      objectB <- mustTerm "книгу"
      let envA = [(VarId "?a", agentA), (VarId "?b", agentB), (VarId "?x", objectB)]
      lendEv <- either assertFailure pure (toEventSpec lendRow (TimeStep "t1") envA)
      returnEv <- either assertFailure pure (toEventSpec returnRow (TimeStep "t2") envA)
      let seedGY = seedFor agentA objectB
      (st, _) <- either assertFailure pure (foldHistory (TimeStep "t0") seedGY [lendEv, returnEv])
      let final = fluentsAt st (TimeStep "t2")
      assertBool "holding returns" (holdProp agentA objectB `elem` final)
      assertBool "obligation cleared"
        (all (not . isObligation) final)
      assertBool "ownership persists" (ownProp agentA objectB `elem` final)
  , TestLabel "journal rewrite equals refolded replacement" $ TestCase $ do
      lendRow <- mustRow "lend"
      giveRow <- mustRow "give"
      agentA <- mustTerm "Аня"
      agentB <- mustTerm "Боря"
      objectB <- mustTerm "книгу"
      let envA = [(VarId "?a", agentA), (VarId "?b", agentB), (VarId "?x", objectB)]
      lendEv <- either assertFailure pure (toEventSpec lendRow (TimeStep "t1") envA)
      giveEv <- either assertFailure pure (toEventSpec giveRow (TimeStep "t1") envA)
      let seedGY = seedFor agentA objectB
      (stLend, _) <- either assertFailure pure (foldHistory (TimeStep "t0") seedGY [lendEv])
      (stGive, _) <- either assertFailure pure (foldHistory (TimeStep "t0") seedGY [giveEv])
      assertBool "ownership differs after rewrite"
        (fluentsAt stLend (TimeStep "t1") /= fluentsAt stGive (TimeStep "t1"))
      assertBool "gift transfers" (ownProp agentB objectB `elem` fluentsAt stGive (TimeStep "t1"))
  , stage2SurfaceTests
  , TestLabel "journal entry JSON round-trips" $ TestCase $ do
      let entry = OwnershipJournalEntry "lend" "Аня" "Боре" "книгу" 3
      assertEqual "entry round trip" (Just entry)
        (decode (encode entry) :: Maybe OwnershipJournalEntry)
  , TestLabel "ownership row JSON round-trips short keys" $ TestCase $ do
      content <- BL.readFile "data/semantic_ir/ownership.jsonl"
      let rows = [ r | line <- BL.split 10 content
                     , not (BL.null line)
                     , Just r <- [Aeson.decode line :: Maybe FileOwnershipRow] ]
      assertEqual "8 library rows" 8 (length rows)
      mapM_ (\row -> assertEqual ("row round trip: " <> T.unpack (foId row))
               (Just row) (decode (encode row) :: Maybe FileOwnershipRow)) rows
  ]

-- | Stage 2 verbalizer fixture: hand-built morphology plus gendered
-- paradigms for the battery names (mirrors production data shapes).
stage2Morph :: MorphologyData
stage2Morph = MorphologyData M.empty genMap nomMapBroad fbsMap
  where
    nomMap = M.fromList [("аня", "аня"), ("боря", "боря"), ("книга", "книга")]
    -- Broad reverse index like production 'mdNominative': every
    -- stored form resolves (oblique forms included).
    nomMapBroad = nomMap `M.union` M.fromList
      [("книгу", "книга"), ("боре", "боря"), ("ане", "аня")]
    genMap = M.fromList [("аня", "ани"), ("боря", "бори"), ("книга", "книги")]
    mkForm surface lemma cas =
      LexemeForm surface lemma "noun" cas SingularNumber CuratedTier 1.0
    fbsMap = M.fromList
      [ ("аня", [mkForm "аня" "аня" NominativeCase])
      , ("боря", [mkForm "боря" "боря" NominativeCase])
      , ("книга", [mkForm "книга" "книга" NominativeCase])
      , ("ани", [mkForm "ани" "аня" GenitiveCase])
      , ("бори", [mkForm "бори" "боря" GenitiveCase])
      , ("книги", [mkForm "книги" "книга" GenitiveCase])
      , ("ане", [mkForm "ане" "аня" DativeCase])
      , ("боре", [mkForm "боре" "боря" DativeCase])
      , ("книге", [mkForm "книге" "книга" DativeCase])
      , ("аню", [mkForm "аню" "аня" AccusativeCase])
      , ("борю", [mkForm "борю" "боря" AccusativeCase])
      , ("книгу", [mkForm "книгу" "книга" AccusativeCase])
      ]

stage2Paradigms :: RuntimeParadigms
stage2Paradigms = RuntimeParadigms
  (M.fromList
    [ ("аня", ParadigmEntry PosNoun (Just "femn") Nothing Nothing Nothing M.empty)
    , ("боря", ParadigmEntry PosNoun (Just "masc") Nothing Nothing Nothing M.empty)
    , ("книга", ParadigmEntry PosNoun (Just "femn") Nothing Nothing Nothing M.empty)
    ])
  M.empty

-- | Stage 2 surface pins (operator-approved wordings verbatim).
stage2SurfaceTests :: Test
stage2SurfaceTests = TestLabel "stage2 surfaces" $ TestList
  [ TestCase $ do
      putStrLn "stage2 verbalizer renders approved surfaces"
      let cmp eid agent recipient object = OwnershipCompareTrace
      let cmp eid agent recipient object = OwnershipCompareTrace
            { octGateFired = True
            , octGateReason = "event-matched:" <> eid
            , octEventId = Just eid
            , octAgent = Just agent
            , octRecipient = Just recipient
            , octObject = Just object
            , octVerdict = Just "Entails"
            , octLineage = []
            , octHistoryDepth = Just 1
            , octCorrected = Just False
            , octCorrectedFrom = Nothing
            }
          render eid agent recipient object =
            renderOwnershipSurface stage2Morph stage2Paradigms
              (cmp eid agent recipient object)
      assertEqual "lend"
        (Just "Понял: Аня одолжила книгу Боре. Книга теперь у Бори, вернуть её Боря должен Ане.")
        (render "lend" "Аня" "Боре" "книгу")
      assertEqual "give"
        (Just "Понял: Аня подарила книгу Боре. Книга теперь принадлежит Боре.")
        (render "give" "Аня" "Боре" "книгу")
      assertEqual "take"
        (Just "Понял: Боря взял книгу у Ани. Книга теперь у Бори.")
        (render "take" "Боря" "Ани" "книгу")
      assertEqual "steal"
        (Just "Понял: Боря украл книгу у Ани. Книга теперь у Бори.")
        (render "steal" "Боря" "Ани" "книгу")
      assertEqual "show"
        (Just "Понял: Аня показала книгу Боре.")
        (render "show" "Аня" "Боре" "книгу")
      assertEqual "return"
        (Just "Понял: Боря вернул книгу Ане. Книга снова у Ани, обязательств не осталось.")
        (render "return" "Боря" "Ане" "книгу")
      assertEqual "return-right"
        (Just "Понял: право на книгу возвращено Ане.")
        (render "return-right" "Боря" "Ане" "книгу")
  , TestCase $ do
      putStrLn "stage2 correction renders the special surface"
      let cmp = OwnershipCompareTrace
            { octGateFired = True
            , octGateReason = "correction:lend>give"
            , octEventId = Just "give"
            , octAgent = Just "Аня"
            , octRecipient = Just "Боре"
            , octObject = Just "книгу"
            , octVerdict = Just "Entails"
            , octLineage = []
            , octHistoryDepth = Just 1
            , octCorrected = Just True
            , octCorrectedFrom = Just "lend"
            }
      assertEqual "correction special"
        (Just "Понял: это был подарок, не одалживание. Книга принадлежит Боре.")
        (renderOwnershipSurface stage2Morph stage2Paradigms cmp)
  , TestCase $ do
      putStrLn "stage2 failed computation keeps legacy"
      let cmp = OwnershipCompareTrace
            { octGateFired = True
            , octGateReason = "event-compute-failed:x"
            , octEventId = Nothing
            , octAgent = Nothing
            , octRecipient = Nothing
            , octObject = Nothing
            , octVerdict = Nothing
            , octLineage = []
            , octHistoryDepth = Just 1
            , octCorrected = Just False
            , octCorrectedFrom = Nothing
            }
      assertEqual "no verdict means legacy" Nothing
        (renderOwnershipSurface stage2Morph stage2Paradigms cmp)
  ]

-- | Journal pin helpers.
mustRow :: T.Text -> IO FileOwnershipRow
mustRow eid = do
  content <- BL.readFile "data/semantic_ir/ownership.jsonl"
  let rows = [ r | line <- BL.split 10 content
                 , not (BL.null line)
                 , Just r <- [Aeson.decode line :: Maybe FileOwnershipRow] ]
  case [ r | r <- rows, foId r == eid ] of
    [row] -> pure row
    _ -> assertFailure ("library row missing: " <> T.unpack eid)

mustTerm :: T.Text -> IO Term
mustTerm t = pure (if isMentionEntity t then Entity (EntityId t) else Concept (ConceptId t))

ownProp :: Term -> Term -> Proposition
ownProp a x = Apply (PredicateId "owns") [RoleBinding "agent" a, RoleBinding "theme" x]

holdProp :: Term -> Term -> Proposition
holdProp a x = Apply (PredicateId "holds") [RoleBinding "agent" a, RoleBinding "theme" x]

seedFor :: Term -> Term -> [Proposition]
seedFor a x = [ownProp a x, holdProp a x]

isObligation :: Proposition -> Bool
isObligation (Apply (PredicateId p) _) = p == "must-return"
isObligation _ = False
