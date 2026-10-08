{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.Semantic.Ownership
Description : canonical — ownership contract row types (contracts only).

Stage-1 / cutover contract types with no logic: the file row
shape for the ownership contract library plus its JSON
instances. Parsing into 'EventSpec' \/ strict rules lives in
'QxFx0.Semantic.IRState', which imports this module — never
the reverse.
-}
module QxFx0.Types.Semantic.Ownership
  ( FileOwnershipRow(..)
  , OwnershipJournalEntry(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), (.=))
import qualified Data.Aeson as Aeson
import Data.Text (Text)
import GHC.Generics (Generic)

-- | One ownership-library row: an event template or a strict rule.
-- Times stay scenario-bound (callers assign them).
data FileOwnershipRow = FileOwnershipRow
  { foId :: !Text
  , foKind :: !Text
  , foPreconditions :: ![Text]
  , foWithdraws :: ![Text]
  , foAsserts :: ![Text]
  , foPremises :: ![Text]
  , foConclusion :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | Short keys matching the @ownership.jsonl@ file schema
-- (NOT the record field names): encode and decode agree, so
-- persisted session state round-trips.
instance ToJSON FileOwnershipRow where
  toJSON row = Aeson.object
    [ "id" .= foId row
    , "kind" .= foKind row
    , "preconditions" .= foPreconditions row
    , "withdraws" .= foWithdraws row
    , "asserts" .= foAsserts row
    , "premises" .= foPremises row
    , "conclusion" .= foConclusion row
    ]

-- | One journal line: a fired ownership event with its explicit
-- participant mentions plus the turn label. Texts only (never
-- structures): EventSpecs rebuild deterministically from the
-- library, so persistence stays trivially versionable.
data OwnershipJournalEntry = OwnershipJournalEntry
  { ojeEvent :: !Text
  , ojeAgent :: !Text
  , ojeRecipient :: !Text
  , ojeObject :: !Text
  , ojeTurn :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON, NFData)

instance FromJSON FileOwnershipRow where
  parseJSON = Aeson.withObject "FileOwnershipRow" $ \o -> FileOwnershipRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "kind"
    <*> o Aeson..:? "preconditions" Aeson..!= []
    <*> o Aeson..:? "withdraws" Aeson..!= []
    <*> o Aeson..:? "asserts" Aeson..!= []
    <*> o Aeson..:? "premises" Aeson..!= []
    <*> o Aeson..:? "conclusion"
