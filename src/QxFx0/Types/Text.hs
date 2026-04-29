{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Text
  ( finalizeForce
  , ensureQuestion
  , ensureSentence
  , fmtPct
  , textShow
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types (IllocutionaryForce(..))

finalizeForce :: IllocutionaryForce -> Text -> Text
finalizeForce IFAsk = ensureQuestion
finalizeForce IFAssert = ensureSentence
finalizeForce IFOffer = ensureSentence
finalizeForce IFConfront = ensureSentence
finalizeForce IFContact = ensureSentence

ensureQuestion :: Text -> Text
ensureQuestion t =
  let trimmed = T.strip t
  in if T.null trimmed
       then "?"
       else case T.unsnoc trimmed of
         Just (_, '?') -> trimmed
         Just (rest, '.') -> rest <> "?"
         _ -> trimmed <> "?"

ensureSentence :: Text -> Text
ensureSentence t =
  let trimmed = T.strip t
  in if T.null trimmed
       then "."
       else case T.unsnoc trimmed of
         Just (_, '.') -> trimmed
         Just (rest, '?') -> rest <> "."
         Just (_, '!') -> trimmed
         _ -> trimmed <> "."

fmtPct :: Double -> Text
fmtPct x = T.pack (show (fromIntegral (round (x * 100) :: Int) :: Int)) <> "%"

textShow :: Show a => a -> Text
textShow = T.pack . show
