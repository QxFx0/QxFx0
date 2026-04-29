{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Readiness
  ( AgdaVerificationStatus(..)
  , agdaVerificationReady
  , agdaVerificationStatusText
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), withText)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

data AgdaVerificationStatus
  = AgdaVerified
  | AgdaMissingWitness
  | AgdaDecodeFailed
  | AgdaVersionMismatch
  | AgdaMissingInput
  | AgdaHashMismatch
  | AgdaUnexpectedInput
  | AgdaInvalid
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData)

agdaVerificationReady :: AgdaVerificationStatus -> Bool
agdaVerificationReady AgdaVerified = True
agdaVerificationReady _ = False

agdaVerificationStatusText :: AgdaVerificationStatus -> Text
agdaVerificationStatusText status =
  case status of
    AgdaVerified -> "verified"
    AgdaMissingWitness -> "missing_witness"
    AgdaDecodeFailed -> "decode_failed"
    AgdaVersionMismatch -> "version_mismatch"
    AgdaMissingInput -> "missing_input"
    AgdaHashMismatch -> "hash_mismatch"
    AgdaUnexpectedInput -> "unexpected_input"
    AgdaInvalid -> "invalid"

instance ToJSON AgdaVerificationStatus where
  toJSON = toJSON . agdaVerificationStatusText

instance FromJSON AgdaVerificationStatus where
  parseJSON = withText "AgdaVerificationStatus" $ \raw ->
    case T.toLower (T.strip raw) of
      "verified" -> pure AgdaVerified
      "missing_witness" -> pure AgdaMissingWitness
      "decode_failed" -> pure AgdaDecodeFailed
      "version_mismatch" -> pure AgdaVersionMismatch
      "missing_input" -> pure AgdaMissingInput
      "hash_mismatch" -> pure AgdaHashMismatch
      "unexpected_input" -> pure AgdaUnexpectedInput
      "invalid" -> pure AgdaInvalid
      other -> fail ("Unknown AgdaVerificationStatus: " <> T.unpack other)
