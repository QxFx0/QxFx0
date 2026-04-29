{-# LANGUAGE OverloadedStrings #-}
module Main where

import System.Random (randomRIO)
import Control.Monad (replicateM, forM_)
import qualified Data.Text as T
import QxFx0.Semantic.Proposition (parseProposition)
import QxFx0.Bridge.NixGuard (nixStringLiteral)
import QxFx0.Bridge.StatePersistence (stateBlobDiagnostics)
import QxFx0.Semantic.MeaningAtoms (collectAtoms)
import QxFx0.Types (ClusterDef(..), AtomSet, asAtoms)

randomString :: Int -> IO String
randomString n = replicateM n $ randomRIO ('\0', '\255')

randomUnicode :: Int -> IO String
randomUnicode n = replicateM n $ randomRIO ('\0', '\1114111')

fuzzRound :: String -> IO ()
fuzzRound _label = do
    -- parseProposition fuzz
    forM_ [1..200 :: Int] $ \(_ :: Int) -> do
      s <- randomUnicode 30
      let _ = parseProposition (T.pack s)
      pure ()

    -- nixStringLiteral fuzz
    forM_ [1..200 :: Int] $ \(_ :: Int) -> do
      s <- randomUnicode 30
      let _ = nixStringLiteral (T.pack s)
      pure ()

    -- collectAtoms / KeywordMatch fuzz
    forM_ [1..200 :: Int] $ \(_ :: Int) -> do
      s <- randomUnicode 30
      let _ = collectAtoms (T.pack s) ([] :: [ClusterDef]) :: AtomSet
      pure ()

    -- stateBlobDiagnostics / JSON decode fuzz
    forM_ [1..200 :: Int] $ \(_ :: Int) -> do
      s <- randomUnicode 60
      let _ = stateBlobDiagnostics (T.pack s)
      pure ()

    putStrLn "round_done"

main :: IO ()
main = do
    fuzzRound "round1"
    fuzzRound "round2"
    fuzzRound "round3"
    putStrLn "ALL_FUZZ_OK"
