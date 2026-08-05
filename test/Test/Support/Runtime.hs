module Test.Support.Runtime
  ( module Runtime
  , bootstrapSession
  ) where

import qualified Data.Text
import QxFx0.Runtime as Runtime hiding (bootstrapSession)
import qualified QxFx0.Runtime as Production

import Test.Support.SessionRegistry (registerTestSession)

-- Test environment scopes own every raw bootstrap result. Production callers
-- should prefer withBootstrappedSession or bracket bootstrapSession themselves.
bootstrapSession :: Bool -> Data.Text.Text -> IO Session
bootstrapSession quiet sessionId =
  Production.bootstrapSession quiet sessionId >>= registerTestSession
