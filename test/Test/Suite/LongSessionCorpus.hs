{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.LongSessionCorpus
  ( longSessionCorpusTests
  ) where

import Control.Exception (try)
import Control.Monad (foldM)
import qualified Data.Text as T
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))

import Test.HUnit (Test(..), assertBool, assertFailure)

import QxFx0.ExceptionPolicy (QxFx0Exception(..))
import QxFx0.Self.Essence
  ( Essence(..)
  , etAngstLevel
  , etWitnesses
  )
import QxFx0.Types (SystemState(..))
import QxFx0.Types.State.SelfState (SelfState(..))

import qualified QxFx0.Runtime as Runtime
  ( Session(..)
  , bootstrapSession
  , runTurnInSession
  )

import Test.Support (withRuntimeEnv)

longSessionCorpusTests :: [Test]
longSessionCorpusTests =
  [ TestLabel "long-session dialogical commitment" $
      TestCase (runLongSessionFixture "dialogical-commitment.jsonl")
  , TestLabel "long-session contemplative commitment" $
      TestCase (runLongSessionFixture "contemplative-commitment.jsonl")
  , TestLabel "long-session integrative no commitment" $
      TestCase (runLongSessionFixture "integrative-no-commitment.jsonl")
  , TestLabel "long-session conatus erosion" $
      TestCase (runLongSessionFixture "conatus-erosion.jsonl")
  , TestLabel "long-session mixed divergence" $
      TestCase (runLongSessionFixture "mixed-divergence.jsonl")
  ]

runLongSessionFixture :: FilePath -> IO ()
runLongSessionFixture filename = do
  root <- getCurrentDirectory
  let fixturePath = root </> "test/fixtures/long-sessions" </> filename
  inputs <- fmap T.pack . lines <$> readFile fixturePath
  withRuntimeEnv ("long-session-" <> filename) $
    do
      session0 <- Runtime.bootstrapSession True "long-session-test"
      let step (turnIdx, sess) input = do
            result <- try (Runtime.runTurnInSession sess input)
                          :: IO (Either QxFx0Exception (Runtime.Session, T.Text))
            case result of
              Left err ->
                assertFailure ("turn " ++ show turnIdx ++ " raised: " ++ show err)
              Right (sess', _) -> do
                let ss = Runtime.sessSystemState sess'
                    angst = case selfEssence (ssSelfState ss) of
                              EssenceUncommitted t -> etAngstLevel t
                              EssenceCommitted t _ -> etAngstLevel t
                    wits  = case selfEssence (ssSelfState ss) of
                              EssenceUncommitted t -> length (etWitnesses t)
                              EssenceCommitted t _ -> length (etWitnesses t)
                assertBool ("angst out of [0,1] at turn " ++ show turnIdx)
                  (angst >= 0.0 && angst <= 1.0)
                assertBool ("witness count must increase at turn " ++ show turnIdx)
                  (wits == turnIdx)
                pure (turnIdx + 1, sess')
      (_, finalSession) <- foldM step (1, session0) inputs
      let finalAngst = case selfEssence (ssSelfState (Runtime.sessSystemState finalSession)) of
                         EssenceUncommitted t -> etAngstLevel t
                         EssenceCommitted t _ -> etAngstLevel t
      assertBool "final angst must be non-negative" (finalAngst >= 0.0)
