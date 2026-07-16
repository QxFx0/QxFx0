{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Lexicon.Expanded.PGFBridge where

import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Lexicon.Expanded.Types

-- | The PGFBridge provides a way to a map a resolved surface form back to a GF-compatible
-- representation. Since PGF requires internal IDs (e.g., "logika_N"), the bridge
-- suggests how to "inject" the surface form into a GF-expression.
data PGFInjection = PGFInjection
  { pgfExpr   :: !Text -- ^ The GF expression to use, e.g. "ExternalLexeme(\"свободы\")"
  , pgfReason :: !Text -- ^ Why this injection was used (e.g. "TierAlgorithmic fallback")
  } deriving (Show, Eq)

-- | Bridge a morphology response to a PGF injection.
bridgeToPGF :: MorphologyResponse -> PGFInjection
bridgeToPGF res = 
  let 
    surface = resSurface res
    reason = "Resolved via " <> resSource res <> " (Tier: " <> (T.pack . show $ resTier res) <> ")"
  in PGFInjection 
     { pgfExpr = "ExternalLexeme(\"" <> surface <> "\")" 
     , pgfReason = reason
     }
