module Test.Support.SessionRegistry
  ( registerTestSession
  , closeRegisteredTestSessions
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar, swapMVar)
import Control.Exception (finally, mask_)
import System.IO.Unsafe (unsafePerformIO)

import qualified QxFx0.Runtime as Runtime

registeredSessions :: MVar [Runtime.Session]
{-# NOINLINE registeredSessions #-}
registeredSessions = unsafePerformIO (newMVar [])

registerTestSession :: Runtime.Session -> IO Runtime.Session
registerTestSession session = do
  modifyMVar_ registeredSessions (pure . (session :))
  pure session

closeRegisteredTestSessions :: IO ()
closeRegisteredTestSessions = mask_ $ do
  sessions <- swapMVar registeredSessions []
  closeAll sessions
  where
    closeAll [] = pure ()
    closeAll (session : rest) =
      Runtime.closeSession session `finally` closeAll rest
