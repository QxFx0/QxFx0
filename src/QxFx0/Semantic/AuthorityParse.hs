{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical — Production authority parse handle (F-11).

Wraps 'QxFx0.Runtime.PGF.parseClaimAstGf' in a session-scoped handle
that loads the PGF grammar once at bootstrap and reuses it for all
subsequent parses within the session.
-}
module QxFx0.Semantic.AuthorityParse
  ( AuthorityParseHandle
  , newAuthorityParseHandle
  , parseWithHandle
  , parseWithHandlePure
  ) where

import Control.Exception (try, IOException)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import qualified PGF2 as PGF
import System.Directory (doesFileExist)
import Prelude

import QxFx0.Semantic.Authority.GfExprParse (gfExprToClaimAst)
import QxFx0.Types.State.SemanticCommitment (FactualClaimPayload)
import QxFx0.Render.Authority (AuthoritySurface(..), claimAstToFactualClaim, parseAuthoritySurfacePattern)

defaultPgfPath :: FilePath
defaultPgfPath = "spec/gf/QxFx0Syntax.pgf"

data AuthorityParseHandle = AuthorityParseHandle
  { aphConcRus :: !PGF.Concr
  , aphConcEng :: !PGF.Concr
  , aphStartCat :: !PGF.Type
  }

newAuthorityParseHandle :: Maybe FilePath -> IO (Either Text AuthorityParseHandle)
newAuthorityParseHandle mPath = do
  let pgfPath = maybe defaultPgfPath id mPath
  exists <- doesFileExist pgfPath
  if not exists
    then pure (Left ("authority_parse_handle: pgf_missing:" <> T.pack pgfPath))
    else do
      result <- try (PGF.readPGF pgfPath) :: IO (Either IOException PGF.PGF)
      case result of
        Left e -> pure (Left ("authority_parse_handle: pgf_exception:" <> T.pack (show e)))
        Right pgf ->
          let langs = PGF.languages pgf
          in case (Map.lookup "QxFx0SyntaxRus" langs, Map.lookup "QxFx0SyntaxEng" langs) of
               (Just rus, Just eng) ->
                 pure (Right AuthorityParseHandle
                   { aphConcRus  = rus
                   , aphConcEng  = eng
                   , aphStartCat = PGF.startCat pgf
                   })
               _ -> pure (Left "authority_parse_handle: required languages not found in pgf")

parseWithHandle :: AuthorityParseHandle -> Text -> Maybe FactualClaimPayload
parseWithHandle h surface =
  case PGF.parse (aphConcRus h) (aphStartCat h) (T.unpack surface) of
    PGF.ParseOk ((expr, _) : _) ->
      case gfExprToClaimAst (T.pack (PGF.showExpr [] expr)) of
        Right ast -> Just (claimAstToFactualClaim surface ast)
        Left _    -> parseAuthoritySurfacePattern (AuthoritySurface surface)
    _ -> parseAuthoritySurfacePattern (AuthoritySurface surface)

{-# NOINLINE parseWithHandlePure #-}
parseWithHandlePure :: AuthorityParseHandle -> AuthoritySurface -> Maybe FactualClaimPayload
parseWithHandlePure h (AuthoritySurface surface) = parseWithHandle h surface
