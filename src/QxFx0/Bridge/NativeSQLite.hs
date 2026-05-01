{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE ForeignFunctionInterface #-}
module QxFx0.Bridge.NativeSQLite
  ( Database
  , Statement
  , open
  , close
  , prepare
  , step
  , stepRow
  , bindText
  , bindInt
  , bindDouble
  , columnText
  , columnInt
  , columnDouble
  , columnIsNull
  , finalize
  , execSql
  , withStatement
  , withDatabase
  , sqliteTransient
  ) where

import Control.Exception (finally)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import qualified Data.ByteString as BS
import Foreign hiding (void)
import Foreign.C.Types (CInt(..), CDouble(..))
import Foreign.C.String (CString, withCString, peekCString)
import QxFx0.ExceptionPolicy (throwQxFx0, QxFx0Exception(SQLiteError))

data CDatabase
data CStatement

type Database = Ptr CDatabase
type Statement = Ptr CStatement

foreign import ccall unsafe "sqlite3_open"
  c_sqlite3_open :: CString -> Ptr Database -> IO CInt

foreign import ccall unsafe "sqlite3_close"
  c_sqlite3_close :: Database -> IO CInt

foreign import ccall unsafe "sqlite3_prepare_v2"
  c_sqlite3_prepare_v2 :: Database -> CString -> CInt -> Ptr Statement -> Ptr CString -> IO CInt

foreign import ccall unsafe "sqlite3_step"
  c_sqlite3_step :: Statement -> IO CInt

foreign import ccall unsafe "sqlite3_finalize"
  c_sqlite3_finalize :: Statement -> IO CInt

foreign import ccall unsafe "sqlite3_bind_text"
  c_sqlite3_bind_text :: Statement -> CInt -> CString -> CInt -> Ptr () -> IO CInt

foreign import ccall unsafe "sqlite3_bind_int"
  c_sqlite3_bind_int :: Statement -> CInt -> CInt -> IO CInt

foreign import ccall unsafe "sqlite3_bind_double"
  c_sqlite3_bind_double :: Statement -> CInt -> CDouble -> IO CInt

foreign import ccall unsafe "sqlite3_column_text"
  c_sqlite3_column_text :: Statement -> CInt -> IO CString

foreign import ccall unsafe "sqlite3_column_int"
  c_sqlite3_column_int :: Statement -> CInt -> IO CInt

foreign import ccall unsafe "sqlite3_column_double"
  c_sqlite3_column_double :: Statement -> CInt -> IO CDouble

foreign import ccall unsafe "sqlite3_column_type"
  c_sqlite3_column_type :: Statement -> CInt -> IO CInt

foreign import ccall unsafe "sqlite3_column_bytes"
  c_sqlite3_column_bytes :: Statement -> CInt -> IO CInt

foreign import ccall unsafe "sqlite3_exec"
  c_sqlite3_exec :: Database -> CString -> Ptr () -> Ptr () -> Ptr CString -> IO CInt

foreign import ccall unsafe "sqlite3_errmsg"
  c_sqlite3_errmsg :: Database -> IO CString

sqliteTransient :: Ptr ()
sqliteTransient = nullPtr `plusPtr` (-1)

sqlOk, sqlRow, sqlDone :: CInt
sqlOk   = 0
sqlRow  = 100
sqlDone = 101

sqlNullType :: CInt
sqlNullType = 5

open :: FilePath -> IO (Either Text Database)
open path = alloca $ \ppDb -> do
  rc <- withCString path $ \cPath -> c_sqlite3_open cPath ppDb
  if rc == sqlOk
    then do db <- peek ppDb
            return (Right db)
    else return (Left $ "sqlite3_open failed: " <> T.pack (show rc))

close :: Database -> IO ()
close db = do
  rc <- c_sqlite3_close db
  if rc /= sqlOk
    then throwQxFx0 (SQLiteError $ T.pack $ "sqlite3_close failed: " ++ show rc)
    else return ()

prepare :: Database -> Text -> IO (Either Text Statement)
prepare db sql = alloca $ \ppStmt -> alloca $ \ppTail -> do
  let sqlBs = TE.encodeUtf8 sql
  rc <- BS.useAsCString sqlBs $ \cSql ->
    c_sqlite3_prepare_v2 db cSql (-1) ppStmt ppTail
  if rc == sqlOk
    then do stmt <- peek ppStmt
            if stmt == nullPtr
              then return (Left "sqlite3_prepare_v2 returned null statement")
              else return (Right stmt)
    else do errMsg <- getErrMsg db
            return (Left $ "prepare failed: " <> errMsg)

getErrMsg :: Database -> IO Text
getErrMsg db = do
  cStr <- c_sqlite3_errmsg db
  if cStr == nullPtr
    then return "<no error message>"
    else T.pack <$> peekCString cStr

step :: Statement -> IO (Either Text CInt)
step stmt = do
  rc <- c_sqlite3_step stmt
  if rc == sqlRow
    then return (Right sqlRow)
    else if rc == sqlDone
         then return (Right sqlDone)
         else return (Left $ "step failed: " <> T.pack (show rc))

stepRow :: Statement -> IO Bool
stepRow stmt = do
  rc <- c_sqlite3_step stmt
  return (rc == sqlRow)

bindText :: Statement -> CInt -> Text -> IO (Either Text ())
bindText stmt idx val = do
  let bs = TE.encodeUtf8 val
  rc <- BS.useAsCString bs $ \cStr ->
    c_sqlite3_bind_text stmt idx cStr (fromIntegral (BS.length bs)) sqliteTransient
  if rc == sqlOk
    then return (Right ())
    else return (Left $ "bindText failed: " <> T.pack (show rc))

bindInt :: Statement -> CInt -> Int -> IO (Either Text ())
bindInt stmt idx val = do
  rc <- c_sqlite3_bind_int stmt idx (fromIntegral val)
  if rc == sqlOk
    then return (Right ())
    else return (Left $ "bindInt failed: " <> T.pack (show rc))

bindDouble :: Statement -> CInt -> Double -> IO (Either Text ())
bindDouble stmt idx val = do
  rc <- c_sqlite3_bind_double stmt idx (realToFrac val)
  if rc == sqlOk
    then return (Right ())
    else return (Left $ "bindDouble failed: " <> T.pack (show rc))

columnText :: Statement -> CInt -> IO Text
columnText stmt idx = do
  cStr <- c_sqlite3_column_text stmt idx
  if cStr == nullPtr
    then return ""
    else do
      cLen <- c_sqlite3_column_bytes stmt idx
      bs <- BS.packCStringLen (cStr, fromIntegral cLen)
      return (TE.decodeUtf8With lenientDecode bs)

columnInt :: Statement -> CInt -> IO Int
columnInt stmt idx = fromIntegral <$> c_sqlite3_column_int stmt idx

columnDouble :: Statement -> CInt -> IO Double
columnDouble stmt idx = realToFrac <$> c_sqlite3_column_double stmt idx

columnIsNull :: Statement -> CInt -> IO Bool
columnIsNull stmt idx = do
  ty <- c_sqlite3_column_type stmt idx
  return (ty == sqlNullType)

finalize :: Statement -> IO ()
finalize stmt = do
  rc <- c_sqlite3_finalize stmt
  if rc /= sqlOk
    then throwQxFx0 (SQLiteError $ T.pack $ "sqlite3_finalize failed: " ++ show rc)
    else return ()

execSql :: Database -> Text -> IO (Either Text ())
execSql db sql = do
  let sqlBs = TE.encodeUtf8 sql
  rc <- BS.useAsCString sqlBs $ \cSql ->
    c_sqlite3_exec db cSql nullPtr nullPtr nullPtr
  if rc == sqlOk
    then return (Right ())
    else do errMsg <- getErrMsg db
            return (Left $ "exec failed: " <> errMsg)

withStatement :: Database -> Text -> (Statement -> IO a) -> IO (Either Text a)
withStatement db sql action = do
  mStmt <- prepare db sql
  case mStmt of
    Left err -> return (Left err)
    Right stmt -> do
      result <- action stmt `finally` finalize stmt
      return (Right result)

withDatabase :: FilePath -> (Database -> IO a) -> IO (Either Text a)
withDatabase path action = do
  mDb <- open path
  case mDb of
    Left err -> return (Left err)
    Right db -> do
      result <- action db `finally` close db
      return (Right result)
