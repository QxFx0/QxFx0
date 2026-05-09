{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Types.SemanticConfig
  ( SemanticConfig(..)
  , emptySemanticConfig
  , defaultSemanticConfig
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), genericParseJSON, defaultOptions, fieldLabelModifier)
import Data.Char (toLower)
import Data.Text (Text)
import GHC.Generics (Generic)

data SemanticConfig = SemanticConfig
  { scBayesianDefineLemmas     :: ![Text]
  , scBayesianCompareLemmas    :: ![Text]
  , scBayesianConfrontLemmas   :: ![Text]
  , scBayesianSupportLemmas  :: ![Text]
  , scBayesianConfusedLemmas   :: ![Text]
  , scTensionDistressLemmas    :: ![Text]
  , scDialogModifierKeywords   :: ![Text]
  , scDialogAgreementKeywords  :: ![Text]
  , scDialogDisagreementKeywords :: ![Text]
  , scDialogNegationKeywords   :: ![Text]
  , scParsePronouns            :: ![Text]
  , scParsePrepositions        :: ![Text]
  , scParseParticles           :: ![Text]
  , scParseAdverbs             :: ![Text]
  , scParseConjunctions        :: ![Text]
  , scParseAdjEndings          :: ![Text]
  , scParseVerbEndings         :: ![Text]
  , scColloquialMode           :: !Bool
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance FromJSON SemanticConfig where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = \lbl -> case lbl of
        ('s':'c':rest) -> drop 1 (camelToSnake rest)
        _              -> map toLower lbl
    }

camelToSnake :: String -> String
camelToSnake [] = []
camelToSnake (c:cs)
  | c `elem` ['A'..'Z'] = '_' : toLower c : camelToSnake cs
  | otherwise = c : camelToSnake cs

emptySemanticConfig :: SemanticConfig
emptySemanticConfig = SemanticConfig
  { scBayesianDefineLemmas     = []
  , scBayesianCompareLemmas    = []
  , scBayesianConfrontLemmas   = []
  , scBayesianSupportLemmas  = []
  , scBayesianConfusedLemmas   = []
  , scTensionDistressLemmas    = []
  , scDialogModifierKeywords   = []
  , scDialogAgreementKeywords  = []
  , scDialogDisagreementKeywords = []
  , scDialogNegationKeywords   = []
  , scParsePronouns            = []
  , scParsePrepositions        = []
  , scParseParticles           = []
  , scParseAdverbs             = []
  , scParseConjunctions        = []
  , scParseAdjEndings          = []
  , scParseVerbEndings         = []
  , scColloquialMode           = True
  }

-- | Same values as the shipped resources/semantics/keywords.json,
--   inlined so tests and pure contexts have a sensible default.
defaultSemanticConfig :: SemanticConfig
defaultSemanticConfig = SemanticConfig
  { scBayesianDefineLemmas     = ["что","такое","определение","значит","определи"]
  , scBayesianCompareLemmas    = ["разница","отличие","сравни","различие","похоже","сходство"]
  , scBayesianConfrontLemmas   = ["неправильно","ошибка","неверно","спорно","возражаю","нет"]
  , scBayesianSupportLemmas  = ["помоги","поддержи","одиноко","один","трудно","грустно","тяжело"]
  , scBayesianConfusedLemmas   = ["непонятно","запутался","запуталась","объясни","не понимаю","неясно"]
  , scTensionDistressLemmas    = ["грустно","тоскливо","страшно","тревожно","плохо","одиноко","устал","устала","больно","тяжело","бесит","раздражает"]
  , scDialogModifierKeywords   = ["коротко","подробно","только","конкретно","ещё","еще","просто","иначе"]
  , scDialogAgreementKeywords  = ["верно","согласен","согласна","именно","точно","правильно"]
  , scDialogDisagreementKeywords = ["неверно","не согласен","не согласна","ошибаешься","спорно"]
  , scDialogNegationKeywords   = ["не"]
  , scParsePronouns            = ["я","ты","он","она","оно","мы","вы","они","меня","тебя","его","её","ее","нас","вас","их","мой","твой","свой","наш","ваш","этот","тот","кто","что","какой","который","где","куда","откуда","мне","тебе","ему","ей","нам","вам","им"]
  , scParsePrepositions        = ["в","на","с","у","за","по","от","до","к","под","про","для","о","об","при","из","со","над","между","перед"]
  , scParseParticles           = ["не","ни","нет","бы","ли","же","только","даже","вот","уже"]
  , scParseAdverbs             = ["коротко","подробно","конкретно","ещё","еще","просто","иначе","грустно","тоскливо","страшно","тревожно","плохо","одиноко","больно","тяжело","непонятно","неясно","верно","точно","правильно","неверно"]
  , scParseConjunctions        = ["и","а","но","или","что","чтобы","как","если","когда","потому","поэтому"]
  , scParseAdjEndings          = ["ый","ий","ая","ое","ие","ые","ого","его","ой","ей","ому","ему","ых","их","им","ыми","ими","ом","ем"]
  , scParseVerbEndings         = ["ть","ти","чь","ться","тся","л","ла","ло","ли","те","й","ь","у","ю","ем","им","ят","ут","ют","ешь","ешься","ет","ется","ишь","ит","ится"]
  , scColloquialMode           = True
  }
