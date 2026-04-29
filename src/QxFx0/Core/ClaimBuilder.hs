{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-| Claim scoring/selection utilities used by planning and identity context merge. -}
module QxFx0.Core.ClaimBuilder
  ( scoreClaims
  , selectTopClaims
  , deduplicateClaims
  , agencyValid
  , tensionValid
  ) where

import QxFx0.Types (IdentityClaimRef(..), SubjectState(..))
import QxFx0.Types.Thresholds
  ( claimConceptMatchWeight
  , claimConfidenceWeight
  , claimTextMatchWeight
  , claimTopicMatchWeight
  , criticalTensionThreshold
  , lowAgencyThreshold
  )
import QxFx0.Core.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsKeywordPhrase
  )
import Data.Text (Text)
import Data.List (sortBy, nubBy)

scoreClaims :: [IdentityClaimRef] -> Text -> [(IdentityClaimRef, Double)]
scoreClaims claims focusEntity =
  map (\c -> (c, claimScore c focusEntity)) claims

claimScore :: IdentityClaimRef -> Text -> Double
claimScore claim focus =
  let focusTokens = tokenizeKeywordText focus
      conceptMatch = if containsKeywordPhrase focusTokens (icrConcept claim) then claimConceptMatchWeight else 0.0
      topicMatch = if containsKeywordPhrase focusTokens (icrTopic claim) then claimTopicMatchWeight else 0.0
      textMatch = if containsKeywordPhrase (tokenizeKeywordText (icrText claim)) focus then claimTextMatchWeight else 0.0
      confWeight = icrConfidence claim * claimConfidenceWeight
  in conceptMatch + topicMatch + textMatch + confWeight

selectTopClaims :: Int -> [(IdentityClaimRef, Double)] -> [IdentityClaimRef]
selectTopClaims n scored =
  let sorted = sortBy (\(_, a) (_, b) -> compare b a) scored
  in take n (map fst sorted)

deduplicateClaims :: [IdentityClaimRef] -> [IdentityClaimRef]
deduplicateClaims = nubBy (\a b -> icrConcept a == icrConcept b && icrTopic a == icrTopic b)

agencyValid :: SubjectState -> Bool
agencyValid ss = ssAgency ss >= lowAgencyThreshold

tensionValid :: SubjectState -> Bool
tensionValid ss = ssTension ss <= criticalTensionThreshold
