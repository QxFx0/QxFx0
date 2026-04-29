{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Input.Lexicon
  ( guessPartOfSpeech
  , guessMorphFeatures
  , semanticClassesForToken
  , discourseFunctionsForToken
  , lemmaForToken
  , isFunctionWord
  , isWorldNoun
  , isMentalNoun
  , isCapabilityLemma
  , isAssistanceLemma
  , isIdentityLemma
  , isGenerativeRequestLemma
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (fromMaybe)

import QxFx0.Semantic.Input.Model
import QxFx0.Semantic.Input.GeneratedLexicon (generatedFormToLemma, generatedLemmaToPos, generatedLemmaToSem)

guessPartOfSpeech :: Text -> InputPartOfSpeech
guessPartOfSpeech token =
  case posOverride (lemmaForToken token) of
    Just forcedPos -> forcedPos
    Nothing ->
      case generatedLemmaToPos (lemmaForToken token) of
        Just pos -> pos
        Nothing
          | token `elem` prepositions -> PosPreposition
          | token `elem` conjunctions -> PosConjunction
          | token `elem` particles -> PosParticle
          | token `elem` interjections -> PosInterjection
          | token `elem` pronouns -> PosPronoun
          | token `elem` numerals -> PosNumeral
          | isVerbLike token -> PosVerb
          | isAdjectiveLike token -> PosAdjective
          | isAdverbLike token -> PosAdverb
          | isNounLike token -> PosNoun
          | otherwise -> PosUnknown

guessMorphFeatures :: Text -> [InputMorphFeature]
guessMorphFeatures token =
  concat
    [ if token == "не" then [FeatNegated] else []
    , if token `elem` firstPerson then [FeatPerson1] else []
    , if token `elem` secondPerson then [FeatPerson2] else []
    , if token `elem` pluralHints then [FeatNumberPlur] else []
    , if token `elem` singularHints then [FeatNumberSing] else []
    ]

semanticClassesForToken :: Text -> [InputSemanticClass]
semanticClassesForToken token =
  let lemma = lemmaForToken token
      genSem = generatedLemmaToSem lemma
  in case semanticOverride lemma of
      Just forcedSem -> forcedSem
      Nothing ->
        if not (null genSem) then genSem else
          if token `elem` selfReferenceTokens then [SemSelfReference]
          else if token `elem` userReferenceTokens then [SemUserReference]
          else if isIdentityLemma lemma then [SemIdentity]
          else if isWorldNoun token then [SemWorldObject]
          else if isMentalNoun token then [SemMentalObject]
          else if token `elem` knowledgeTokens then [SemKnowledge]
          else if token `elem` comparisonTokens then [SemComparison]
          else if token `elem` causeTokens then [SemCause]
          else if token `elem` invitationTokens then [SemDialogueInvitation]
          else if token `elem` repairTokens then [SemDialogueRepair]
          else if token `elem` contemplativeTokens then [SemContemplative]
          else if isVerbLike token then [SemAction]
          else if isAdjectiveLike token || isAdverbLike token then [SemState]
          else [SemUnknown]

posOverride :: Text -> Maybe InputPartOfSpeech
posOverride lemma =
  case lemma of
    "привет" -> Just PosInterjection
    "здравствуй" -> Just PosInterjection
    "здравствуйте" -> Just PosInterjection
    "салют" -> Just PosInterjection
    "хай" -> Just PosInterjection
    _ -> Nothing

semanticOverride :: Text -> Maybe [InputSemanticClass]
semanticOverride lemma
  | lemma `elem` ["привет", "здравствуй", "здравствуйте", "салют", "хай"] =
      Just [SemDialogueInvitation]
  | otherwise = Nothing

discourseFunctionsForToken :: Text -> [InputDiscourseFunction]
discourseFunctionsForToken token =
  concat
    [ if token == "не" then [DiscNegation] else []
    , if token `elem` questionMarkers then [DiscQuestion] else []
    , if token `elem` contrastMarkers then [DiscContrast] else []
    , if token `elem` conditionMarkers then [DiscCondition] else []
    , if token `elem` causeMarkers then [DiscCause] else []
    , if token `elem` resultMarkers then [DiscResult] else []
    , if token `elem` invitationTokens then [DiscInvitation] else []
    , if token `elem` clarifyMarkers then [DiscClarification] else []
    , if token `elem` emphasisMarkers then [DiscEmphasis] else []
    ]

lemmaForToken :: Text -> Text
lemmaForToken token =
  fromMaybe (fallbackLemma token) (generatedFormToLemma token)

fallbackLemma :: Text -> Text
fallbackLemma token =
  case token of
    "мне" -> "я"
    "меня" -> "я"
    "мной" -> "я"
    "тобой" -> "ты"
    "тебе" -> "ты"
    "тебя" -> "ты"
    "нас" -> "мы"
    "вами" -> "вы"
    "солнца" -> "солнце"
    "мысли" -> "мысль"
    "логике" -> "логика"
    "умею" -> "уметь"
    "умеешь" -> "уметь"
    "умеет" -> "уметь"
    "умеем" -> "уметь"
    "умеют" -> "уметь"
    "могу" -> "мочь"
    "можешь" -> "мочь"
    "может" -> "мочь"
    "можем" -> "мочь"
    "можете" -> "мочь"
    "могут" -> "мочь"
    "помогу" -> "помочь"
    "поможешь" -> "помочь"
    "поможет" -> "помочь"
    "поможем" -> "помочь"
    "поможете" -> "помочь"
    "помогут" -> "помочь"
    "являешься" -> "являться"
    "являюсь" -> "являться"
    "является" -> "являться"
    "такой" -> "такой"
    "такая" -> "такой"
    "такое" -> "такой"
    "такие" -> "такой"
    "логичное" -> "логичный"
    "логичная" -> "логичный"
    "логичный" -> "логичный"
    "логично" -> "логичный"
    "интересную" -> "интересный"
    "интересная" -> "интересный"
    "интересное" -> "интересный"
    "новую" -> "новый"
    "другую" -> "другой"
    "купил" -> "купить"
    "купила" -> "купить"
    "купили" -> "купить"
    "куплю" -> "купить"
    "купишь" -> "купить"
    "купит" -> "купить"
    "живу" -> "жить"
    "живешь" -> "жить"
    "живёт" -> "жить"
    "живет" -> "жить"
    "живем" -> "жить"
    "живём" -> "жить"
    "живете" -> "жить"
    "живёте" -> "жить"
    "живут" -> "жить"
    "оказался" -> "оказаться"
    "оказалась" -> "оказаться"
    "оказалось" -> "оказаться"
    "оказались" -> "оказаться"
    "оказывается" -> "оказаться"
    "голубая" -> "голубой"
    "голубое" -> "голубой"
    "голубые" -> "голубой"
    "голубого" -> "голубой"
    "голубому" -> "голубой"
    "дома" -> "дом"
    "говорим" -> "говорить"
    "говоришь" -> "говорить"
    "говорит" -> "говорить"
    "говорю" -> "говорить"
    "говорят" -> "говорить"
    "говорите" -> "говорить"
    "разговариваем" -> "разговаривать"
    "разговариваешь" -> "разговаривать"
    "разговаривает" -> "разговаривать"
    "разговаривают" -> "разговаривать"
    _ -> token

isFunctionWord :: Text -> Bool
isFunctionWord token =
  token `elem` (prepositions <> conjunctions <> particles <> questionMarkers <> contrastMarkers <> causeMarkers)

isWorldNoun :: Text -> Bool
isWorldNoun token = token `elem` worldNouns

isMentalNoun :: Text -> Bool
isMentalNoun token = token `elem` mentalNouns

isCapabilityLemma :: Text -> Bool
isCapabilityLemma lemma = lemma `elem` ["уметь", "мочь"]

isAssistanceLemma :: Text -> Bool
isAssistanceLemma lemma = lemma `elem` ["помочь", "помощь"]

isIdentityLemma :: Text -> Bool
isIdentityLemma lemma = lemma `elem` ["кто", "что", "быть", "являться", "такой"]

isGenerativeRequestLemma :: Text -> Bool
isGenerativeRequestLemma lemma = lemma `elem` ["сказать", "скажи", "дать", "дай", "сформулировать", "сформулируй"]

isVerbLike :: Text -> Bool
isVerbLike token =
  token `elem` commonVerbs
    || any (`T.isSuffixOf` token)
      [ "ть", "ти", "чь"
      , "ю", "у", "ем", "ешь", "ет", "ют", "ут", "ешься", "ется", "емся", "етесь"
      , "ил", "ила", "или", "ал", "ала", "али", "ался", "алась", "алось", "ались"
      ]

isAdjectiveLike :: Text -> Bool
isAdjectiveLike token =
  any (`T.isSuffixOf` token)
    [ "ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие"
    , "ого", "ему", "ыми", "ых"
    ]

isAdverbLike :: Text -> Bool
isAdverbLike token =
  token `elem` adverbs
    || any (`T.isSuffixOf` token) ["о", "е"]

isNounLike :: Text -> Bool
isNounLike token =
  token `elem` worldNouns
    || token `elem` mentalNouns
    || any (`T.isSuffixOf` token)
      [ "а", "я", "о", "е", "и", "ы", "ь", "ие", "ия", "ость", "ение", "изм" ]

prepositions, conjunctions, particles, interjections, pronouns, numerals :: [Text]
prepositions =
  [ "в", "во", "на", "к", "ко", "у", "о", "об", "обо", "от", "до", "по", "из", "изо", "с", "со", "без", "для", "при", "перед", "между", "про", "над", "под" ]
conjunctions =
  [ "и", "или", "а", "но", "если", "чтобы", "потому", "потому-что", "когда", "хотя", "либо" ]
particles =
  [ "не", "ни", "ли", "же", "бы", "вот", "только", "лишь", "даже", "пусть", "давай", "разве", "неужели" ]
interjections = ["эй", "ах", "ох", "увы", "ого", "ну"]
pronouns =
  [ "я", "ты", "он", "она", "оно", "мы", "вы", "они"
  , "мне", "меня", "мной", "тебя", "тебе", "тобой", "нас", "вам", "вами", "вас"
  , "мой", "твой", "наш", "ваш", "себя", "это", "этот", "эта", "эти", "кто", "что"
  ]
numerals = ["ноль", "один", "два", "три", "четыре", "пять", "десять", "сто", "первый", "второй", "третий"]

questionMarkers, contrastMarkers, conditionMarkers, causeMarkers, resultMarkers, clarifyMarkers, emphasisMarkers :: [Text]
questionMarkers = ["что", "кто", "где", "когда", "почему", "зачем", "как", "ли"]
contrastMarkers = ["но", "а", "однако", "зато"]
conditionMarkers = ["если", "когда"]
causeMarkers = ["потому", "поскольку", "из-за", "оттого"]
resultMarkers = ["поэтому", "значит", "следовательно", "итак"]
clarifyMarkers = ["уточни", "поясни", "разъясни", "что-значит", "что значит"]
emphasisMarkers = ["именно", "как-раз", "точно", "ведь", "же", "вот"]

invitationTokens, repairTokens, contemplativeTokens, knowledgeTokens, comparisonTokens, causeTokens :: [Text]
invitationTokens = ["поговорим", "обсудим", "рассмотрим", "давай", "говорить", "говорим", "говоришь", "разговаривать", "разговариваем"]
repairTokens = ["не", "понимаю", "разрыв", "контакт", "потерян", "потеря", "сбой"]
contemplativeTokens = ["тишина", "дом", "любовь", "смерть", "время", "смысл", "душа", "свобода", "страх", "память", "я"]
knowledgeTokens = ["знаешь", "знание", "известно", "понимаешь", "понятие", "определение", "значит"]
comparisonTokens = ["или", "логичнее", "вероятнее", "естественнее", "правильнее", "лучше", "хуже"]
causeTokens = ["почему", "причина", "следствие", "из-за", "поэтому", "потому"]

worldNouns, mentalNouns, adverbs, commonVerbs, selfReferenceTokens, userReferenceTokens, firstPerson, secondPerson, pluralHints, singularHints :: [Text]
worldNouns =
  [ "солнце", "земля", "мир", "дождь", "вода", "огонь", "время", "пространство"
  , "звезда", "дом", "город", "лес", "море", "река", "камень", "ветер", "космос"
  , "небо", "осень", "человек", "люди", "бог", "правда", "ложь"
  ]
mentalNouns =
  [ "мысль", "идея", "смысл", "логика", "память", "воображение", "сознание", "разум"
  , "внимание", "фокус", "знание", "понимание"
  ]
adverbs =
  [ "быстро", "медленно", "сейчас", "потом", "здесь", "там", "очень", "почти", "теперь", "вчера", "сегодня" ]
commonVerbs =
  [ "знаю", "знаешь", "знает", "думать", "думаю", "думаешь", "сказать", "скажи", "говорю", "говоришь"
  , "работаю", "работаешь", "работает", "поговорим", "обсудим", "понимаю", "понимаешь"
    , "говорить", "говорю", "говоришь", "говорит", "говорим", "говорят", "говорите"
    , "разговаривать", "разговариваю", "разговариваешь", "разговаривает", "разговариваем", "разговаривают"
    , "купить", "купил", "купила", "купили", "жить", "живу", "живет", "живём", "живут"
    , "оказаться", "оказался", "оказалась", "оказалось", "оказались", "делать", "делаю", "делаешь", "делает"
  ]
selfReferenceTokens = ["я", "мне", "меня", "мой", "моя", "моё", "мы"]
userReferenceTokens = ["ты", "тебя", "тебе", "твой", "твоя", "твое", "вы", "вас"]
firstPerson = ["я", "мне", "меня", "мы", "наш", "мой"]
secondPerson = ["ты", "тебя", "тебе", "вы", "вас", "ваш", "твой"]
pluralHints = ["мы", "вы", "они", "эти", "люди"]
singularHints = ["я", "ты", "он", "она", "оно", "этот", "эта", "это"]
