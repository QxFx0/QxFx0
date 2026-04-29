{-# LANGUAGE OverloadedStrings #-}

{-| Runtime query helpers over identity claims, scenes, and maintenance operations. -}
module QxFx0.Bridge.SQLite.Queries
  ( queryIdentityClaimsByFocus
  , maybeCheckpoint
  , loadScenes
  , loadClusters
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.ExceptionPolicy (QxFx0Exception(SQLiteError), throwQxFx0)
import QxFx0.Types
  ( ClusterDef(..)
  , IdentityClaimRef(..)
  , SemanticScene(..)
  )

queryIdentityClaimsByFocus :: NSQL.Database -> [Text] -> IO [IdentityClaimRef]
queryIdentityClaimsByFocus db keywords =
  case keywords of
    [] -> queryTopClaims db
    keyword : rest -> do
      claims <- queryExactTrigger db keyword
      if not (null claims)
        then pure claims
        else do
          ftsClaims <- queryFTS5 db keyword
          if not (null ftsClaims)
            then pure ftsClaims
            else do
              topicClaims <- queryTopicFallback db keyword
              if not (null topicClaims)
                then pure topicClaims
                else queryIdentityClaimsByFocus db rest

queryExactTrigger :: NSQL.Database -> Text -> IO [IdentityClaimRef]
queryExactTrigger db keyword = do
  let sql = "SELECT concept, text, confidence, source, topic FROM identity_claims WHERE concept = ? LIMIT 10"
  stmt <- prepareQuery db "queryExactTrigger" sql
  _ <- NSQL.bindText stmt 1 keyword
  claims <- collectClaims stmt
  NSQL.finalize stmt
  pure claims

queryFTS5 :: NSQL.Database -> Text -> IO [IdentityClaimRef]
queryFTS5 db keyword = do
  let sql = "SELECT concept, text, confidence, source, topic FROM identity_claims WHERE id IN (SELECT rowid FROM identity_claims_fts WHERE text MATCH ? LIMIT 10)"
  stmt <- prepareQuery db "queryFTS5" sql
  _ <- NSQL.bindText stmt 1 keyword
  claims <- collectClaims stmt
  NSQL.finalize stmt
  pure claims

queryTopicFallback :: NSQL.Database -> Text -> IO [IdentityClaimRef]
queryTopicFallback db topic = do
  let sql = "SELECT concept, text, confidence, source, topic FROM identity_claims WHERE topic = ? LIMIT 10"
  stmt <- prepareQuery db "queryTopicFallback" sql
  _ <- NSQL.bindText stmt 1 topic
  claims <- collectClaims stmt
  NSQL.finalize stmt
  pure claims

queryTopClaims :: NSQL.Database -> IO [IdentityClaimRef]
queryTopClaims db = do
  let sql = "SELECT concept, text, confidence, source, topic FROM identity_claims ORDER BY confidence DESC, id ASC LIMIT 10"
  stmt <- prepareQuery db "queryTopClaims" sql
  claims <- collectClaims stmt
  NSQL.finalize stmt
  pure claims

collectClaims :: NSQL.Statement -> IO [IdentityClaimRef]
collectClaims stmt = go []
  where
    go acc = do
      hasRow <- NSQL.stepRow stmt
      if hasRow
        then do
          concept <- NSQL.columnText stmt 0
          text_ <- NSQL.columnText stmt 1
          conf <- NSQL.columnDouble stmt 2
          source <- NSQL.columnText stmt 3
          topic <- NSQL.columnText stmt 4
          go (IdentityClaimRef concept text_ conf source topic : acc)
        else pure (reverse acc)

maybeCheckpoint :: NSQL.Database -> Int -> IO ()
maybeCheckpoint db turnCount =
  when (turnCount > 0 && turnCount `mod` 100 == 0) $ do
    _ <- NSQL.execSql db "PRAGMA wal_checkpoint(TRUNCATE);"
    pure ()
  where
    when True action = action
    when False _ = pure ()

loadScenes :: NSQL.Database -> IO [SemanticScene]
loadScenes db = do
  let sql = "SELECT MIN(confidence), MAX(confidence), topic, topic FROM identity_claims GROUP BY topic"
  stmt <- prepareQuery db "loadScenes" sql
  scenes <- collectScenes stmt
  NSQL.finalize stmt
  pure scenes
  where
    collectScenes stmt = go []
      where
        go acc = do
          hasRow <- NSQL.stepRow stmt
          if hasRow
            then do
              minC <- NSQL.columnDouble stmt 0
              maxC <- NSQL.columnDouble stmt 1
              desc <- NSQL.columnText stmt 2
              _ <- NSQL.columnText stmt 3
              go (SemanticScene minC maxC [] desc : acc)
            else pure (reverse acc)

loadClusters :: NSQL.Database -> IO [ClusterDef]
loadClusters db = do
  let sql = "SELECT name, keywords, priority FROM semantic_clusters ORDER BY priority DESC"
  stmt <- prepareQuery db "loadClusters" sql
  clusters <- collectClusters stmt
  NSQL.finalize stmt
  pure clusters
  where
    collectClusters stmt = go []
      where
        go acc = do
          hasRow <- NSQL.stepRow stmt
          if hasRow
            then do
              name <- NSQL.columnText stmt 0
              kwText <- NSQL.columnText stmt 1
              prio <- NSQL.columnDouble stmt 2
              let kws = T.splitOn "," kwText
              go (ClusterDef name kws prio : acc)
            else pure (reverse acc)

prepareQuery :: NSQL.Database -> Text -> Text -> IO NSQL.Statement
prepareQuery db ctx sql = do
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err -> throwQxFx0 (SQLiteError ("prepare " <> ctx <> " failed: " <> err))
    Right stmt -> pure stmt
