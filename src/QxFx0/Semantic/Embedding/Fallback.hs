{-# LANGUAGE OverloadedStrings #-}

{-| Deterministic local fallback embedding and vector algebra helpers. -}
module QxFx0.Semantic.Embedding.Fallback
  ( fallbackEmbedding
  , cosineSimilarity
  ) where

import Control.Monad (forM_)
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import QxFx0.Semantic.Embedding.Support (embeddingDim)
import QxFx0.Semantic.Embedding.Types (Embedding)

fallbackEmbedding :: String -> Embedding
fallbackEmbedding input =
  let ws = words (filter (`notElem` (".,!?:;\"'" :: String)) input)
      rawVec = V.create $ do
        v <- MV.replicate embeddingDim 0.0
        forM_ (zip [(0 :: Int) ..] ws) $ \(i, w) -> do
          let h = stableHash w
              idx = abs h `mod` embeddingDim
              val = if h > 0 then 1.0 else -1.0
          curr <- MV.read v idx
          MV.write v idx (curr + val + fromIntegral (i `mod` 3) * 0.1)
        pure v
      norm = magnitude rawVec
   in if norm > 0
        then V.map (/ norm) rawVec
        else V.replicate embeddingDim 0.0

stableHash :: String -> Int
stableHash = go 0
  where
    go acc [] = if acc == 0 then 1 else acc
    go acc (c : cs) = go ((acc * 31 + fromEnum c) `mod` (maxBound `div` 2)) cs

cosineSimilarity :: Embedding -> Embedding -> Float
cosineSimilarity v1 v2
  | m1 == 0 || m2 == 0 = 0.0
  | otherwise =
      let sim = dotProduct v1 v2 / (m1 * m2)
       in if isNaN sim || isInfinite sim then 0.0 else sim
  where
    dotProduct a b = V.sum $ V.zipWith (*) a b
    m1 = magnitude v1
    m2 = magnitude v2

magnitude :: Embedding -> Float
magnitude v = sqrt $ V.sum $ V.map (\x -> x * x) v
