{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Intent.Features
Description : Deterministic semantic feature extraction from raw utterances.

Extracts compositional features from text that describe /what properties/
the utterance has, rather than /what type/ it is. Features are then consumed
by 'QxFx0.Semantic.Intent.Classifier' which combines them compositionally
via rules, not single-keyword triggers.

Invariant: same input → same features, always. Pure, total, deterministic.
-}
module QxFx0.Semantic.Intent.Features
  ( SemanticFeatures(..)
  , extractFeatures
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)

import QxFx0.Semantic.Morphology (extractContentNouns)
import QxFx0.Types (MorphologyData)

-- | Compositional features describing what properties an utterance has.
--
-- Features are atomic observations about syntactic structure, morphology,
-- discourse markers, and semantic roles. They do NOT make classification
-- decisions — that is the job of compositional rules in the Classifier.
--
-- Lexical items in feature fields are /linguistic indicators/, not
-- keyword triggers. The difference:
--
-- * Keyword trigger: "различ" → DistinctionQ (single word decides type)
-- * Feature: sfHasComparisonMark = True (property of utterance)
--   + sfHasTwoConcepts = True (another property)
--   → compositional rule: IntentDistinguish (rules combine features)
data SemanticFeatures = SemanticFeatures
  { sfIsQuestion :: !Bool
    -- ^ Syntactic: is this an interrogative sentence.
    -- Detected by trailing '?' or wh-word presence.
  , sfHasNegation :: !Bool
    -- ^ Morphological: contains negative particle (не, ни, нет, без).
  , sfHasContradiction :: !Bool
    -- ^ Discourse marker: "но", "однако", "противоречит", "вопреки".
    -- Signals the speaker is challenging a prior claim.
  , sfHasTwoConcepts :: !Bool
    -- ^ Semantic roles: extractContentNouns finds ≥2 content nouns.
    -- Signals comparison or distinction intent.
  , sfHasComparisonMark :: !Bool
    -- ^ Lexical indicators of comparison: "между", "от", "или",
    -- "разниц", "различ", "отлич", "сравн", "сопостав".
  , sfHasDefinitionMark :: !Bool
    -- ^ Construction: "что такое", "означает", "это ", "является".
    -- Signals definitional intent.
  , sfHasChallengeMark :: !Bool
    -- ^ Modality: "неверно", "ошибаешься", "спорю", "возраж",
    -- "считаю иначе", "я думаю по-другому".
    -- Signals explicit challenge to a claim.
  , sfHasRepairMark :: !Bool
    -- ^ Discourse: "сломал", "неправиль", "не работает", "ошибк".
    -- Signals a repair/recovery need.
  , sfHasPurposeMark :: !Bool
    -- ^ Construction: "для чего", "зачем", "функци", "имеет ли смысл".
    -- Signals purpose/function inquiry.
  , sfHasWorldCauseMark :: !Bool
    -- ^ Construction: "почему", "отчего", "по какой причине", "как возник".
    -- Signals world-cause inquiry (distinct from self-knowledge).
  , sfHasSelfReference :: !Bool
    -- ^ Pronoun/lexeme: "я", "мой", "мне", "сам", "себя", "лично".
    -- Signals self-referential intent.
  , sfHasContactMark :: !Bool
    -- ^ Greeting/courtesy: "привет", "здравствуй", "как дела",
    -- "добрый день", "hello", "hi".
    -- Signals contact/relationship intent.
  , sfHasDeepenMark :: !Bool
    -- ^ Construction: "подробнее", "углубимся", "раскрой", "продолжай".
    -- Signals desire to deepen the topic.
  , sfHasNextStepMark :: !Bool
    -- ^ Construction: "что дальше", "следующий шаг", "план", "конкретно".
    -- Signals action/next-step intent.
  , sfHasGenerativeMark :: !Bool
    -- ^ Construction: "скажи что-то", "какая мысль", "поразмышляй".
    -- Signals generative/reflective request.
  , sfHasExploratoryMark :: !Bool
    -- ^ Construction: "а если", "что будет если", "представь".
    -- Signals exploratory/hypothetical intent.
  , sfHasAffectiveMark :: !Bool
    -- ^ Emotional lexeme: "устал", "сложновато", "трудно", "спасибо",
    -- "помоги", "поддержи". Signals affective support need.
  , sfHasOperationalMark :: !Bool
    -- ^ Meta-linguistic: "ты работаешь", "ты онлайн", "ты живой",
    -- "что можешь". Signals operational status inquiry.
  , sfHasCompetingDefinition :: !Bool
    -- ^ Compound: first-person assertion ("я считаю", "по-моему",
    -- "на мой взгляд") + definition mark ("это", "—").
    -- Signals the user asserts a competing definition — a challenge.
  , sfTopicComplexity :: !Double
    -- ^ Semantic complexity of extracted topics (0-1).
    -- Higher when multiple abstract nouns present.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Deterministic feature extraction. Same input → same output.
--
-- This function does NOT classify — it only observes properties.
-- Classification is done by 'QxFx0.Semantic.Intent.Classifier.classifyIntent'.
extractFeatures :: Text -> [Text] -> MorphologyData -> SemanticFeatures
extractFeatures rawText tokens _morph =
  let rawLower = T.toLower (T.strip rawText)
      contentNouns = extractContentNouns rawText
      nounCount = length contentNouns
  in SemanticFeatures
    { sfIsQuestion        = extractIsQuestion rawText tokens
    , sfHasNegation       = extractHasNegation tokens
    , sfHasContradiction  = extractHasContradiction rawLower
    , sfHasTwoConcepts    = nounCount >= 2
    , sfHasComparisonMark = extractHasComparisonMark rawLower tokens
    , sfHasDefinitionMark = extractHasDefinitionMark rawLower
    , sfHasChallengeMark  = extractHasChallengeMark rawLower
    , sfHasRepairMark     = extractHasRepairMark rawLower
    , sfHasPurposeMark    = extractHasPurposeMark rawLower
    , sfHasWorldCauseMark = extractHasWorldCauseMark rawLower
    , sfHasSelfReference  = extractHasSelfReference tokens
    , sfHasContactMark    = extractHasContactMark rawLower tokens
    , sfHasDeepenMark     = extractHasDeepenMark rawLower
    , sfHasNextStepMark   = extractHasNextStepMark rawLower
    , sfHasGenerativeMark = extractHasGenerativeMark rawLower
    , sfHasExploratoryMark = extractHasExploratoryMark rawLower
    , sfHasAffectiveMark  = extractHasAffectiveMark rawLower
    , sfHasOperationalMark = extractHasOperationalMark rawLower
    , sfHasCompetingDefinition = extractHasCompetingDefinition rawLower
    , sfTopicComplexity   = fromIntegral nounCount / 5.0
    }

-- ---------------------------------------------------------------------------
-- Individual feature extractors (each is pure, total, deterministic)
-- ---------------------------------------------------------------------------

extractIsQuestion :: Text -> [Text] -> Bool
extractIsQuestion rawText tokens =
  "?" `T.isSuffixOf` T.strip rawText
  || any (`elem` tokens) ["что", "как", "почему", "зачем", "когда", "кто", "где", "сколько"]

extractHasNegation :: [Text] -> Bool
extractHasNegation = any (`elem` ["не", "ни", "нет", "без"])

extractHasContradiction :: Text -> Bool
extractHasContradiction rawLower =
  any (`T.isInfixOf` rawLower)
    [ "противореч", "но ", "однако", "вопреки", "неверно"
    , "это не так", "не согласен", "не верю"
    ]

extractHasComparisonMark :: Text -> [Text] -> Bool
extractHasComparisonMark rawLower tokens =
     any (`elem` tokens) ["между", "от", "или", "и"]
  || any (`T.isInfixOf` rawLower)
       [ "разниц", "различ", "отлич", "сравн", "сопостав"
       , "versus", "vs"
       ]

extractHasDefinitionMark :: Text -> Bool
extractHasDefinitionMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "что такое", "означает", "является", "представляет собой"
    , "это ", "определени"
    ]

extractHasChallengeMark :: Text -> Bool
extractHasChallengeMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "неверно", "ошибаешься", "не прав", "спорю", "возраж"
    , "считаю иначе", "я думаю по-другому", "а если посмотреть"
    , "не совсем так", "не точн", "разве", "не согласен"
    , "не согласна", "сомневаюсь", "оспариваю", "ты говоришь"
    ]

extractHasRepairMark :: Text -> Bool
extractHasRepairMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "сломал", "неправиль", "не работает", "ошибк", "баг"
    , "проблем", "сбой", "глюч", "плохо работает"
    ]

extractHasPurposeMark :: Text -> Bool
extractHasPurposeMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "для чего", "зачем", "функци", "имеет ли смысл"
    , "в чём смысл", "какова цель"
    ]

extractHasWorldCauseMark :: Text -> Bool
extractHasWorldCauseMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "почему", "отчего", "по какой причине", "как возник"
    , "откуда берёт", "что вызыва"
    ]

extractHasSelfReference :: [Text] -> Bool
extractHasSelfReference = any (`elem` ["я", "мой", "мне", "сам", "себя", "лично"])

extractHasContactMark :: Text -> [Text] -> Bool
extractHasContactMark rawLower tokens =
     any (`elem` tokens) ["привет", "здравствуй", "хай", "hello", "hi"]
  || any (`T.isInfixOf` rawLower)
       [ "как дела", "как жизнь", "добрый день", "доброе утро"
       , "добрый вечер", "добрый вечер", "салют"
       ]

extractHasDeepenMark :: Text -> Bool
extractHasDeepenMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "подробнее", "углубимся", "раскрой", "продолжай"
    , "расскажи больше", "ещё раз", "еще раз"
    ]

extractHasNextStepMark :: Text -> Bool
extractHasNextStepMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "что дальше", "следующий шаг", "план", "конкретно"
    , "как действовать", "что делать"
    ]

extractHasGenerativeMark :: Text -> Bool
extractHasGenerativeMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "скажи что-то", "скажи интересную мысль", "какая мысль"
    , "поразмышляй", "что думаешь", "какова твоя мысль"
    , "что ты думаешь", "твоя мысль о", "твое мнение о"
    , "твоё мнение о", "как ты считаешь", "как ты видишь"
    ]

extractHasExploratoryMark :: Text -> Bool
extractHasExploratoryMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "а если", "что будет если", "представь", "допустим"
    , "как выглядит если", "что если бы"
    ]

extractHasAffectiveMark :: Text -> Bool
extractHasAffectiveMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "устал", "сложновато", "трудно", "спасибо", "благодар"
    , "помоги", "поддержи", "тяжело", "надоело"
    ]

extractHasOperationalMark :: Text -> Bool
extractHasOperationalMark rawLower =
  any (`T.isInfixOf` rawLower)
    [ "ты работаешь", "ты онлайн", "ты живой", "что можешь"
    , "что ты умеешь", "какой ты", "что ты знаешь"
    ]

extractHasCompetingDefinition :: Text -> Bool
extractHasCompetingDefinition rawLower =
  let hasFirstPersonAssertion =
        any (`T.isInfixOf` rawLower)
          [ "я считаю", "по-моему", "на мой взгляд", "я думаю что"
          , "я полагаю", "мне кажется что", "по моему мнению"
          ]
      hasDefinitionConstruction =
        any (`T.isInfixOf` rawLower)
          [ "это просто", "это и есть", "— это", "это не", "это всего лишь"
          , "это лишь", "означает просто", "сводится к"
          ]
      hasDash = " — " `T.isInfixOf` rawLower
      -- Reduction/equivalence patterns that work without first person:
      -- "X — это просто Y", "X не более чем Y", "разве X не просто Y"
      hasReductionPattern =
        any (`T.isInfixOf` rawLower)
          [ "это просто", "просто слабость", "не более чем"
          , "разве не просто", "это всего лишь", "не более чем"
          , "сводится к", "это лишь"
          ]
  in (hasFirstPersonAssertion && (hasDefinitionConstruction || hasDash))
     || hasReductionPattern
