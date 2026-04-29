{-# LANGUAGE DerivingStrategies, OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Bridge.NixCache
  ( NixCache
  , newNixCache
  , cachedNixEval
  ) where

import QxFx0.Bridge.NixGuard (checkConstitution)
import QxFx0.Types (NixGuardStatus(..))
import Data.Text (Text)
import qualified Data.Text as T
import Data.IORef (IORef, newIORef, readIORef, atomicModifyIORef')
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.List (sortBy)

data NixResult
  = NixSuccess !Text
  | NixError !Text
  deriving stock (Eq, Show)

data CacheEntry = CacheEntry
  { ceResult :: !NixResult
  , ceTimestamp :: !UTCTime
  } deriving stock (Eq, Show)

data NixCache = NixCache
  { ncRef :: !(IORef (Map Text CacheEntry))
  , ncTTL :: !Double
  , ncMaxEntries :: !Int
  }

newNixCache :: Double -> Int -> IO NixCache
newNixCache ttl maxEntries = do
  ref <- newIORef M.empty
  return NixCache { ncRef = ref, ncTTL = ttl, ncMaxEntries = maxEntries }

nixCacheLookup :: NixCache -> Text -> IO (Maybe NixResult)
nixCacheLookup cache key = do
  now <- getCurrentTime
  m <- readIORef (ncRef cache)
  case M.lookup key m of
    Nothing -> return Nothing
    Just entry ->
      let age = diffUTCTime now (ceTimestamp entry)
      in if realToFrac age > ncTTL cache
         then return Nothing
         else return (Just (ceResult entry))

nixCacheInsert :: NixCache -> Text -> NixResult -> IO ()
nixCacheInsert cache key result = do
  now <- getCurrentTime
  let entry = CacheEntry result now
  atomicModifyIORef' (ncRef cache) $ \m ->
    let m' = M.insert key entry m
    in if M.size m' > ncMaxEntries cache
       then (evictToHalf (ncMaxEntries cache) m', ())
       else (m', ())

evictToHalf :: Int -> Map Text CacheEntry -> Map Text CacheEntry
evictToHalf maxEntries m
  | M.size m <= 100 = m
  | otherwise =
      let entries = M.toList m
          sorted = sortBy (\(_,a) (_,b) -> compare (ceTimestamp a) (ceTimestamp b)) entries
          target = maxEntries `div` 2
          keep = drop (length sorted - target) sorted
      in M.fromList keep

checkWithCache :: NixCache -> FilePath -> Text -> Double -> Double -> IO NixGuardStatus
checkWithCache cache nixPath concept agency tension = do
  let key = concept <> "|" <> renderKeyPart agency <> "|" <> renderKeyPart tension
  mResult <- nixCacheLookup cache key
  case mResult of
    Just (NixSuccess "true")  -> return Allowed
    Just (NixSuccess "false") -> return (Blocked "constitution blocked (cached)")
    Just (NixSuccess _)       -> return (Unavailable "cache payload mismatch")
    Just (NixError _)         -> do
      status <- checkConstitution nixPath concept agency tension
      case status of
        Allowed      -> nixCacheInsert cache key (NixSuccess "true")
        Blocked _    -> nixCacheInsert cache key (NixSuccess "false")
        Unavailable r -> nixCacheInsert cache key (NixError r)
      return status
    Nothing -> do
      status <- checkConstitution nixPath concept agency tension
      case status of
        Allowed      -> nixCacheInsert cache key (NixSuccess "true")
        Blocked _    -> nixCacheInsert cache key (NixSuccess "false")
        Unavailable r -> nixCacheInsert cache key (NixError r)
      return status
  where
    renderKeyPart :: Double -> Text
    renderKeyPart = T.pack . show

cachedNixEval :: NixCache -> FilePath -> Text -> Double -> Double -> IO NixGuardStatus
cachedNixEval = checkWithCache
