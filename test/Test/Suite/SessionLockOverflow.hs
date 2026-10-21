{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{-| Audit 2026-10-16 п.27 anti-rot: eviction under cap pressure must
never split a session's critical section, pins must be released on
every exit path, and unpinned entries must keep being evicted.
-}
module Test.Suite.SessionLockOverflow
  ( sessionLockOverflowTests
  ) where

import Control.Concurrent
  ( forkIO
  , newEmptyMVar
  , putMVar
  , takeMVar
  , threadDelay
  )
import Control.Concurrent.Async (mapConcurrently_)
import Control.Exception (SomeException, throwIO, try)
import Control.Monad (forM_)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import System.Timeout (timeout)
import Test.HUnit

import QxFx0.Core.SessionLock
  ( SessionLockStats(..)
  , newSessionLockManagerWithCap
  , sessionLockStats
  , withSessionLock
  , withSessionLockPaused
  )

sessionLockOverflowTests :: [Test]
sessionLockOverflowTests =
  [ TestLabel "eviction cannot split a session's critical section"
      testEvictionCannotSplitSession
  , TestLabel "stress: same-session entries stay serialized at cap 1"
      testStressSerialization
  , TestLabel "a throwing action releases its pin"
      testPinReleasedOnException
  , TestLabel "unpinned entries keep being evicted at the cap"
      testEvictionAccounting
  , TestLabel "a held lock is visible as pinned"
      testPinnedCountVisible
  ]

-- | Deterministic reproduction of the eviction race:
--
-- 1. A registers session \"a\" and pauses before acquiring its MVar;
-- 2. B forces the cap pressure (evicting the free \"a\" entry on the
--    unfixed code, overflowing on the fixed one);
-- 3. A resumes and enters the critical section;
-- 4. C asks for \"a\" again: on the unfixed code it creates a new lock
--    and enters concurrently; with pins it must wait for A.
testEvictionCannotSplitSession :: Test
testEvictionCannotSplitSession = TestCase $ do
  mgr <- newSessionLockManagerWithCap 1
  aReady <- newEmptyMVar
  aContinue <- newEmptyMVar
  aInside <- newEmptyMVar
  aRelease <- newEmptyMVar
  aDone <- newEmptyMVar
  cEntered <- newEmptyMVar
  cDone <- newEmptyMVar
  _ <- forkIO $ do
    withSessionLockPaused mgr "a"
      (putMVar aReady () >> takeMVar aContinue)
      (putMVar aInside () >> takeMVar aRelease)
    putMVar aDone ()
  takeMVar aReady
  -- Cap pressure while "a" is registered but not yet acquired.
  withSessionLock mgr "b" (pure ())
  putMVar aContinue ()
  takeMVar aInside
  _ <- forkIO $ do
    withSessionLock mgr "a" (putMVar cEntered ())
    putMVar cDone ()
  premature <- timeout 500000 (takeMVar cEntered)
  assertBool "a second call for the same session must not enter while the first is inside"
    (premature == Nothing)
  putMVar aRelease ()
  takeMVar aDone
  queued <- timeout 2000000 (takeMVar cEntered)
  assertBool "the queued call must enter after the first releases"
    (queued /= Nothing)
  takeMVar cDone
  stats <- sessionLockStats mgr
  assertEqual "all pins must be released" 0 (slsPinnedLocks stats)

-- | Probabilistic net: many concurrent turns over two sessions at
-- cap 1 must never overlap inside one session.
testStressSerialization :: Test
testStressSerialization = TestCase $ do
  mgr <- newSessionLockManagerWithCap 1
  active <- newIORef (M.empty :: M.Map T.Text Int)
  maxSeen <- newIORef (M.empty :: M.Map T.Text Int)
  let worker t =
        forM_ [1 .. 200 :: Int] $ \n -> do
          let sid = if even (t + n) then "a" else "b"
          withSessionLock mgr sid $ do
            cur <- atomicModifyIORef' active $ \m ->
              let c = M.findWithDefault 0 sid m + 1
              in (M.insert sid c m, c)
            atomicModifyIORef' maxSeen $ \m -> (M.insertWith max sid cur m, ())
            threadDelay 1000
            atomicModifyIORef' active $ \m -> (M.adjust (subtract 1) sid m, ())
  mapConcurrently_ worker [1 .. 4 :: Int]
  seen <- readIORef maxSeen
  assertBool ("max concurrent entries per session must be 1, got: " ++ show seen)
    (all (<= 1) (M.elems seen))

testPinReleasedOnException :: Test
testPinReleasedOnException = TestCase $ do
  mgr <- newSessionLockManagerWithCap 1
  result <- try @SomeException $
    withSessionLock mgr "a" (throwIO (userError "boom"))
  case result of
    Left _ -> pure ()
    Right _ -> assertFailure "the action's exception must propagate"
  stats <- sessionLockStats mgr
  assertEqual "a throwing action must release the pin" 0 (slsPinnedLocks stats)

testEvictionAccounting :: Test
testEvictionAccounting = TestCase $ do
  mgr <- newSessionLockManagerWithCap 1
  withSessionLock mgr "a" (pure ())
  statsA <- sessionLockStats mgr
  assertEqual "one tracked entry at the cap" 1 (slsTrackedLocks statsA)
  withSessionLock mgr "b" (pure ())
  statsB <- sessionLockStats mgr
  assertBool "an unpinned free entry must be evicted"
    (slsEvictions statsB > slsEvictions statsA)
  assertEqual "tracked stays at the cap" 1 (slsTrackedLocks statsB)
  assertBool "overflow is active at the cap" (slsOverflowActive statsB)
  assertEqual "no pins after sequential calls" 0 (slsPinnedLocks statsB)
  withSessionLock mgr "c" (pure ())
  statsC <- sessionLockStats mgr
  assertBool "the next overflow session evicts again"
    (slsEvictions statsC > slsEvictions statsB)

testPinnedCountVisible :: Test
testPinnedCountVisible = TestCase $ do
  mgr <- newSessionLockManagerWithCap 4
  inside <- newEmptyMVar
  release <- newEmptyMVar
  done <- newEmptyMVar
  _ <- forkIO $ do
    withSessionLock mgr "a" (putMVar inside () >> takeMVar release)
    putMVar done ()
  takeMVar inside
  stats <- sessionLockStats mgr
  assertBool "a held lock is pinned" (slsPinnedLocks stats >= 1)
  putMVar release ()
  takeMVar done
  statsAfter <- sessionLockStats mgr
  assertEqual "the pin is released" 0 (slsPinnedLocks statsAfter)
