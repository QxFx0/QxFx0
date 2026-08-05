{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Types.Semantic.SurfaceRealizer
Description : Closed contract for an optional LLM surface realization.

The contract makes the LLM a renderer of an already admitted plan.  It is not
an authority source and cannot add claims that are absent from the plan.
-}
module QxFx0.Types.Semantic.SurfaceRealizer
  ( SurfaceRealizerRequest(..)
  , SurfaceRealizerResponse(..)
  , SurfaceRealizerFailure(..)
  , surfaceResponseIsAdmissible
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.ResponsePlan
  ( ResponseSemanticPlan
  , pcId
  , rspClaims
  , responsePlanIsAdmissible
  )

data SurfaceRealizerRequest = SurfaceRealizerRequest
  { srrLanguage :: !Text
  , srrPlan :: !ResponseSemanticPlan
  , srrRequiredMarkers :: ![Text]
  , srrForbiddenPatterns :: ![Text]
  , srrMaxCharacters :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SurfaceRealizerResponse = SurfaceRealizerResponse
  { srsSurface :: !Text
  , srsClaimRefs :: ![Text]
  , srsModeMarkers :: ![Text]
  , srsLanguage :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SurfaceRealizerFailure
  = RealizerTimeout
  | RealizerMalformedResponse
  | RealizerAddedClaim
  | RealizerDroppedClaim
  | RealizerPolicyViolation
  | RealizerQualityRejected
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

surfaceResponseIsAdmissible :: SurfaceRealizerRequest -> SurfaceRealizerResponse -> Bool
surfaceResponseIsAdmissible request response =
    responsePlanIsAdmissible (srrPlan request)
    && srrLanguage request == srsLanguage response
    && not (T.null (srsSurface response))
    && T.length (srsSurface response) <= srrMaxCharacters request
    && sort (srsClaimRefs response) == sort (map pcId (rspClaims (srrPlan request)))
    && all (`contains` srsSurface response) (srrRequiredMarkers request)
    && all (not . (`contains` srsSurface response)) (srrForbiddenPatterns request)
  where
    contains needle haystack = needle `elem` T.words haystack || needle `T.isInfixOf` haystack
