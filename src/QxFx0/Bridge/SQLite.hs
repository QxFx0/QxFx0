{-| SQLite facade for pooling, bootstrap, and runtime query helpers. -}
module QxFx0.Bridge.SQLite
  ( QxFx0DB(..)
  , WorkerDBPool
  , currentSchemaVersion
  , newDBPool
  , closeDBPool
  , withDB
  , withPooledDB
  , queryIdentityClaimsByFocus
  , ensureSchemaMigrations
  , maybeCheckpoint
  , loadScenes
  , loadClusters
  ) where

import QxFx0.Bridge.SQLite.Bootstrap (currentSchemaVersion, ensureSchemaMigrations)
import QxFx0.Bridge.SQLite.Pool
  ( QxFx0DB(..)
  , WorkerDBPool
  , closeDBPool
  , newDBPool
  , withDB
  , withPooledDB
  )
import QxFx0.Bridge.SQLite.Queries
  ( loadClusters
  , loadScenes
  , maybeCheckpoint
  , queryIdentityClaimsByFocus
  )
