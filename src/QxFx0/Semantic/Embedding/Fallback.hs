{-# LANGUAGE OverloadedStrings #-}

{-| Deterministic local fallback embedding and vector algebra helpers. -}
module QxFx0.Semantic.Embedding.Fallback
  ( fallbackEmbedding
  , stableHash
  , cosineSimilarity
  ) where

import Control.Monad (forM_)
import qualified Data.Vector as V
import qualified Data.Vector.Mutable as MV
import qualified Data.Text as T
import QxFx0.Semantic.Embedding.Support (embeddingDim)
import QxFx0.Semantic.Embedding.Types (Embedding)

fallbackEmbedding :: T.Text -> Embedding
fallbackEmbedding input =
  let ws = T.words (T.filter (`notElem` (".,!?:;\"'" :: String)) input)
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

stableHash :: T.Text -> Int
stableHash = go 0
  where
    go acc t
      | T.null t  = if acc == 0 then 1 else acc
      | otherwise =
          case T.uncons t of
            Nothing -> if acc == 0 then 1 else acc
            Just (ch, rest) -> go ((acc * 31 + fromEnum ch) `mod` (maxBound `div` 2)) rest

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
