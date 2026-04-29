{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| User-state and identity/domain-support types plus lightweight text normalization. -}
module QxFx0.Types.Domain.User
  ( UserState(..)
  , ClusterDef(..)
  , IdentityClaimRef(..)
  , normalizeClaimText
  , inferUserState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import Data.Char (isAlphaNum, isPunctuation)
import Data.List (foldl', isPrefixOf, tails)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Config.Domain
  ( defaultUserReadiness
  , defaultUserTone
  )
import QxFx0.Types.Domain.Atoms (Register(..))
import QxFx0.Types.Domain.R5 (SemanticLayer(..))

data UserState = UserState
  { usEmotionalTone :: !Text
  , usNeedLayer :: !SemanticLayer
  , usReadiness :: !Double
  , usDominantRegister :: !Register
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON UserState where
  toJSON = genericToJSON defaultOptions

instance FromJSON UserState where
  parseJSON = genericParseJSON defaultOptions

data ClusterDef = ClusterDef
  { cdName :: !Text
  , cdKeywords :: ![Text]
  , cdPriority :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON ClusterDef where
  toJSON = genericToJSON defaultOptions

instance FromJSON ClusterDef where
  parseJSON = genericParseJSON defaultOptions

data IdentityClaimRef = IdentityClaimRef
  { icrConcept :: !Text
  , icrText :: !Text
  , icrConfidence :: !Double
  , icrSource :: !Text
  , icrTopic :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON IdentityClaimRef where
  toJSON = genericToJSON defaultOptions

instance FromJSON IdentityClaimRef where
  parseJSON = genericParseJSON defaultOptions

normalizeClaimText :: Text -> Text
normalizeClaimText =
  T.intercalate " " . T.words . T.toLower . stripPunct
  where
    stripPunct t =
      let noMd = T.replace "**" "" . T.replace "*" "" . T.replace "#" "" . T.replace "`" "" $ t
      in T.filter (\c -> not (isPunctuation c) || c == '-' || c == '\'') noMd

inferUserState :: [ClusterDef] -> Text -> UserState
inferUserState clusters rawText =
  let tokens = tokenizeDomainText rawText
      matching = filter (\c -> any (containsDomainPhrase tokens) (cdKeywords c)) clusters
      best =
        case matching of
          [] -> Nothing
          (c:cs) -> Just (foldl' (\a b -> if cdPriority b > cdPriority a then b else a) c cs)
      tone =
        case best of
          Nothing -> defaultUserTone
          Just c -> cdName c
      (needLayer, reg) = inferLayerReg tokens
      readiness =
        case best of
          Nothing -> defaultUserReadiness
          Just c -> min 1.0 (cdPriority c)
  in UserState tone needLayer readiness reg
  where
    inferLayerReg tokens
      | containsAnyDomainPhrase tokens ["почему", "зачем", "как", "что такое"] =
          (ContentLayer, Search)
      | containsAnyDomainPhrase tokens ["помоги", "подожди", "одиноко"] =
          (ContactLayer, Contact)
      | containsAnyDomainPhrase tokens ["точно", "конечно", "безусловно"] =
          (ContentLayer, Anchor)
      | otherwise =
          (ContentLayer, Neutral)

tokenizeDomainText :: Text -> [Text]
tokenizeDomainText =
  filter (not . T.null) . T.words . T.map normalizeChar . T.toLower
  where
    normalizeChar ch
      | isAlphaNum ch = ch
      | otherwise = ' '

containsDomainPhrase :: [Text] -> Text -> Bool
containsDomainPhrase haystack phrase =
  let needle = tokenizeDomainText phrase
  in not (null needle) && any (isPrefixOf needle) (tails haystack)

containsAnyDomainPhrase :: [Text] -> [Text] -> Bool
containsAnyDomainPhrase haystack = any (containsDomainPhrase haystack)
