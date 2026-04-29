{-# LANGUAGE OverloadedStrings #-}

{-| Guard rule evaluation over rendered surface segments and dialogue history. -}
module QxFx0.Core.Guard.Checks
  ( postRenderSafetyCheck
  , postRenderSafetyCheckSurface
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.Guard.Types
import QxFx0.Core.Policy.Contracts
  ( driftPatterns
  , guardEmptyResponse
  , guardMarkupLeak
  , guardMetadataLeak
  , guardStuckRepetition
  , guardSuspiciousPatterns
  , guardToxicPatterns
  , guardTooLong
  , injectionPatterns
  , toxicPatterns
  )
import QxFx0.Core.Semantic.KeywordMatch
  ( containsKeywordPhrase
  , tokenizeKeywordText
  )
import QxFx0.Types (normalizeClaimText)

postRenderSafetyCheck :: Text -> [Text] -> SafetyStatus
postRenderSafetyCheck rendered history =
  postRenderSafetyCheckSurface
    GuardSurface
      { gsRenderedText = rendered
      , gsSegments = [RenderSegment SegmentLocalRecovery rendered]
      , gsQuestionLike = T.any (== '?') rendered
      }
    history

postRenderSafetyCheckSurface :: GuardSurface -> [Text] -> SafetyStatus
postRenderSafetyCheckSurface surface history =
  foldl chooseMoreSevere InvariantOK
    [ checkEmptyRealization rendered
    , checkMetadataLeak surface
    , checkStuckRealization rendered history
    , checkIdentityDrift rendered
    , checkToxicity rendered
    , checkLength rendered
    , checkInputInjection surface
    ]
  where
    rendered = gsRenderedText surface

checkEmptyRealization :: Text -> SafetyStatus
checkEmptyRealization text =
  let trimmed = T.strip text
      isEmpty = T.null trimmed || trimmed == "..." || trimmed == "?"
   in if isEmpty
        then InvariantBlock guardEmptyResponse
        else InvariantOK

checkMetadataLeak :: GuardSurface -> SafetyStatus
checkMetadataLeak surface =
  let leakPatterns = ["{topic}", "{left}", "{right}", "{style}", "{move}", "{slot}"]
      found = findInUntrustedSegments leakPatterns surface
   in if null found
        then InvariantOK
        else InvariantBlock (guardMetadataLeak <> T.intercalate ", " found)

checkStuckRealization :: Text -> [Text] -> SafetyStatus
checkStuckRealization rendered history =
  let normalizedRender = normalizeClaimText rendered
      matchCount = length $ filter (\historic -> normalizeClaimText historic == normalizedRender) (take 5 history)
   in if matchCount >= 3
        then InvariantWarn guardStuckRepetition
        else InvariantOK

checkIdentityDrift :: Text -> SafetyStatus
checkIdentityDrift text =
  let lowerText = T.toLower text
      found = filter (`T.isInfixOf` lowerText) driftPatterns
   in if null found
        then InvariantOK
        else InvariantBlock (guardMarkupLeak <> ": " <> T.intercalate ", " found)

checkToxicity :: Text -> SafetyStatus
checkToxicity text =
  let tokens = tokenizeKeywordText text
      found = filter (containsKeywordPhrase tokens) toxicPatterns
   in if null found
        then InvariantOK
        else InvariantWarn (guardToxicPatterns <> T.intercalate ", " found)

checkLength :: Text -> SafetyStatus
checkLength text =
  let len = T.length text
   in if len > 5000
        then InvariantBlock guardTooLong
        else if len == 0
          then InvariantBlock guardEmptyResponse
          else InvariantOK

checkInputInjection :: GuardSurface -> SafetyStatus
checkInputInjection surface =
  let found = findInUntrustedSegments injectionPatterns surface
   in if null found
        then InvariantOK
        else InvariantBlock (guardSuspiciousPatterns <> T.intercalate ", " found)

findInUntrustedSegments :: [Text] -> GuardSurface -> [Text]
findInUntrustedSegments patterns surface =
  filter present patterns
  where
    untrustedTexts =
      [ T.toLower (rsText segment)
      | segment <- gsSegments surface
      , rsKind segment /= SegmentTemplate
      ]
    present pattern =
      let needle = T.toLower pattern
       in any (T.isInfixOf needle) untrustedTexts

chooseMoreSevere :: SafetyStatus -> SafetyStatus -> SafetyStatus
chooseMoreSevere left right
  | severity right > severity left = right
  | otherwise = left

severity :: SafetyStatus -> Int
severity InvariantOK = 0
severity (InvariantWarn _) = 1
severity (InvariantBlock _) = 2
