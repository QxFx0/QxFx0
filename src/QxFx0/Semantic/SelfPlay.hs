{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.SelfPlay
Description : L3 Self-play training: system questions itself, LLM evaluates,
              weak spots become new graph relations.

Training loop:
  1. Generate question from random L1 topic (or cross-topic pair)
  2. System answers via composeContextual (graph traversal)
  3. LLM evaluates: "Is this answer substantive? What's missing?"
  4. If evaluation finds gaps → LLM extracts new relations
  5. Relations go through admission + gates
  6. Admitted relations added to AtomGraph
  7. Next iteration: same question, richer graph

LLM is evaluator + relation extractor only. Never generates dialogue output.
All answers come from graph traversal. Determinism preserved in runtime:
self-play runs offline, enriches graph, runtime serves from enriched graph.
-}
module QxFx0.Semantic.SelfPlay
  ( SelfPlayConfig(..)
  , SelfPlayResult(..)
  , defaultSelfPlayConfig
  , runSelfPlayCycle
  , generateQuestion
  , evaluateAnswer
  , extractGapRelations
  , runSelfPlayIterations
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
import qualified Data.Aeson as A
import Data.List (intercalate, sortBy, nub, filter)
import Data.Maybe (fromMaybe, mapMaybe, isNothing, isJust, listToMaybe)
import Text.Read (readMaybe)
import Data.Ord (comparing, Down(..))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8
import System.Random (randomRIO)
import Control.Monad (replicateM, forM, when)
import System.IO (hPutStrLn, stderr)
import qualified Data.List as L

import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.PathFinder
import QxFx0.Semantic.Content.SubstrateCandidate
import QxFx0.Semantic.Content.GeneratedPredicateGate
import QxFx0.Semantic.PropositionParser
import QxFx0.Semantic.DialogueContext
import QxFx0.Semantic.GraphEngagement
import QxFx0.Semantic.ContextualComposer
import QxFx0.Semantic.LLMDiscovery (LLMConfig(..), defaultLLMConfig, parseLLMRelations, buildDiscoveryPrompt)
import QxFx0.Types (MorphologyData(..))
import qualified Data.Map.Strict as M

-- | Self-play training configuration.
data SelfPlayConfig = SelfPlayConfig
  { spLLMConfig :: !LLMConfig
  , spIterations :: !Int        -- how many question-answer-evaluate cycles
  , spFieldProfile :: !FieldProfile
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Result of one self-play cycle.
data SelfPlayResult = SelfPlayResult
  { sprQuestion :: !Text           -- generated question
  , sprAnswer :: !Text             -- system's answer
  , sprScore :: !Double            -- LLM evaluation score (0-10)
  , sprGaps :: ![Text]             -- identified gaps
  , sprNewRelations :: ![Relation] -- extracted new relations
  , sprAdmittedRelations :: ![Relation] -- relations that passed gates
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Default config: 10 iterations, neutral field profile.
defaultSelfPlayConfig :: Text -> SelfPlayConfig
defaultSelfPlayConfig apiKey = SelfPlayConfig
  { spLLMConfig = defaultLLMConfig apiKey
  , spIterations = 10
  , spFieldProfile = defaultFieldProfile
  }

-- | Run N self-play iterations, enriching the graph after each.
-- Returns all results + the final enriched graph.
runSelfPlayIterations :: SelfPlayConfig -> MorphologyData -> AtomGraph -> IO ([SelfPlayResult], AtomGraph)
runSelfPlayIterations config morph initialGraph = do
  results <- replicateM (spIterations config) (runSelfPlayCycle config morph initialGraph)
  -- Collect all admitted relations across iterations
  let allAdmitted = nub (concatMap sprAdmittedRelations results)
      enrichedGraph = withPromoted allAdmitted initialGraph
  return (results, enrichedGraph)

-- | Run one self-play cycle:
-- 1. Generate question
-- 2. System answers
-- 3. LLM evaluates
-- 4. Extract gap relations
-- 5. Run admission
runSelfPlayCycle :: SelfPlayConfig -> MorphologyData -> AtomGraph -> IO SelfPlayResult
runSelfPlayCycle config morph graph = do
  -- 1. Generate a question from a random L1 topic
  question <- generateQuestion graph
  let topic = extractSubjectFromQuestion question

  -- 2. System answers via contextual composer
  let prop = parseProposition question
      ctx = emptyContext
      engagement = engageWithProposition graph ctx prop
      surface = composeContextual morph (spFieldProfile config) graph ctx prop engagement
      answer = gsText surface

  -- 3. LLM evaluates the answer
  (score, gaps) <- evaluateAnswer (spLLMConfig config) question answer

  -- 4. If score < 7, extract new relations from gaps
  newRelations <- if score < 7
                    then extractGapRelations (spLLMConfig config) topic gaps
                    else return []

  -- 5. Run admission on new relations
  let knownAtoms = allAtomIds
      (admitted, _rejected) = admitCandidates defaultAdmissionConfig knownAtoms
                         (map (\r -> SubstrateCandidate
                             { scFromTopic = relTopic r
                             , scToAtomSurface = case relTo r of AtomId t -> t
                             , scRelTypeGuess = fromMaybe "" (relVerbText r)
                             , scConfidence = 1.0  -- LLM-extracted, high confidence
                             , scSourceSpan = SourceSpan "llm_selfplay" "discovery" "gap"
                             , scRawText = question
                             }) newRelations)
      admittedRelations = promoteAll admitted

  return $ SelfPlayResult
    { sprQuestion = question
    , sprAnswer = answer
    , sprScore = score
    , sprGaps = gaps
    , sprNewRelations = newRelations
    , sprAdmittedRelations = admittedRelations
    }

-- | Generate a question from a random L1 topic.
-- Picks a random topic and creates a "Что такое X?" question.
-- 30% chance: cross-topic question "Как X связан с Y?"
generateQuestion :: AtomGraph -> IO Text
generateQuestion graph = do
  let topics = allTopics
  randIdx <- randomRIO (0, length topics - 1)
  let topic = topics L.!! randIdx

  -- 30% chance of cross-topic question
  isCross <- randomRIO (0, 9 :: Int)
  if isCross < 3 && length topics >= 2
    then do
      randIdx2 <- randomRIO (0, length topics - 1)
      let topic2 = topics L.!! randIdx2
      if topic /= topic2
        then return ("Как " <> topic <> " связан с " <> topic2 <> "?")
        else return ("Что такое " <> topic <> "?")
    else return ("Что такое " <> topic <> "?")

-- | Evaluate an answer using LLM.
-- Returns (score 0-10, list of identified gaps).
evaluateAnswer :: LLMConfig -> Text -> Text -> IO (Double, [Text])
evaluateAnswer config question answer = do
  let prompt = "Ты оцениваешь ответ философской системы.\n"
        <> "Вопрос: " <> question <> "\n"
        <> "Ответ: " <> answer <> "\n\n"
        <> "Оцени ответ по шкале 0-10:\n"
        <> "- 10: глубокий, содержательный, с аргументацией\n"
        <> "- 7: хороший, но не хватает глубины\n"
        <> "- 5: поверхностный, шаблонный\n"
        <> "- 0: пустой или нерелевантный\n\n"
        <> "Формат ответа:\n"
        <> "SCORE: <число>\n"
        <> "GAPS: <что не хватает, через запятую>\n"
  response <- callLLM config prompt
  let (score, gaps) = parseEvaluation response
  return (score, gaps)

-- | Extract new relations from identified gaps using LLM.
extractGapRelations :: LLMConfig -> Text -> [Text] -> IO [Relation]
extractGapRelations config topic gaps = do
  let gapsText = T.intercalate ", " gaps
      prompt = buildDiscoveryPrompt topic
        <> "\n\nДополнительный контекст: в текущих ответах системы не хватает: "
        <> gapsText
        <> ". Сосредоточься на этих аспектах."
  response <- callLLM config prompt
  return $ parseLLMRelations topic response

-- | Call LLM API and return the text response.
callLLM :: LLMConfig -> Text -> IO Text
callLLM config prompt = do
  let requestBody = A.encode $ A.object
        [ "model" A..= llmModel config
        , "max_tokens" A..= (4096 :: Int)
        , "messages" A..= [ A.object
            [ "role" A..= ("user" :: Text)
            , "content" A..= prompt
            ]
          ]
        ]
  let request = (parseRequest_ (T.unpack (llmUrl config)))
        { method = "POST"
        , requestBody = RequestBodyLBS requestBody
        , requestHeaders =
            [ ("Accept", "application/json")
            , ("Content-Type", "application/json")
            , ("Authorization", "Bearer " <> BS8.pack (T.unpack (llmApiKey config)))
            ]
        }
  manager <- newManager tlsManagerSettings
  response <- httpLbs request manager
  let body = responseBody response
  case A.eitherDecode body of
    Right (LLMResponse { lrChoices = choices }) ->
      case choices of
        (choice:_) -> return (mContent (cMessage choice))
        [] -> return ""
    Left err -> do
      hPutStrLn stderr $ "[selfplay] JSON decode error: " <> err
      return ""

-- | Parse LLM evaluation response.
parseEvaluation :: Text -> (Double, [Text])
parseEvaluation response =
  let ls = T.lines response
      scoreLine = listToMaybe [ l | l <- ls, "SCORE:" `T.isInfixOf` l ]
      gapsLine = listToMaybe [ l | l <- ls, "GAPS:" `T.isInfixOf` l ]
      score = case scoreLine of
        Just l -> let after = T.strip (T.drop (T.length "SCORE:") (snd (T.breakOn "SCORE:" l)))
                  in fromMaybe 5.0 (readMaybe (T.unpack after))
        Nothing -> 5.0
      gaps = case gapsLine of
        Just l -> let after = T.strip (T.drop (T.length "GAPS:") (snd (T.breakOn "GAPS:" l)))
                  in filter (not . T.null) (map T.strip (T.splitOn "," after))
        Nothing -> []
  in (score, gaps)

-- | Extract subject topic from a question.
extractSubjectFromQuestion :: Text -> Text
extractSubjectFromQuestion question =
  let lower = T.toLower question
  in if "что такое " `T.isInfixOf` lower
       then T.strip (snd (T.breakOn "что такое " lower))
       else if "как " `T.isPrefixOf` lower
         then T.strip (T.takeWhile (/= ' ') (T.drop 4 lower))
         else "неизвестный"

-- | LLM API response types (same as LLMDiscovery).
data LLMResponse = LLMResponse
  { lrChoices :: ![LLMChoice]
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)

data LLMChoice = LLMChoice
  { cMessage :: !LLMMessage
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)

data LLMMessage = LLMMessage
  { mContent :: !Text
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)

-- | Safe list indexing.
safeIndex :: [a] -> Int -> a
safeIndex lst idx = case drop idx lst of
  (x:_) -> x
  [] -> error "SelfPlay: index out of bounds"
