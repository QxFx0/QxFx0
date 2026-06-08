{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical — Authority surface parser and renderer (F-11).

'parseAuthoritySurface' uses a two-stage approach:

  1. GF-backed parsing via 'QxFx0.Runtime.PGF.parseClaimAstGf' — uses the
     same @spec\/gf\/QxFx0Syntax.pgf@ grammar as the linearizer so that the
     full round-trip @ast → linearize → parse → ast@ is closed.
  2. Pattern-matching fallback for the four canonical commitment-statement
     forms (en\/ru UserIs, en\/ru TopicIs) when GF parsing fails or is
     unavailable.

The GF path handles the full 'ClaimAst' vocabulary; the pattern-matching
path is a bounded compatibility layer for the initial authority subset.
-}
module QxFx0.Render.Authority
  ( AuthoritySurface(..)
  , emptyAuthoritySurface
  , isStubAuthoritySurface
  , parseAuthoritySurface
  , parseAuthoritySurfaceIO
  , parseAuthoritySurfacePattern
  , claimAstToFactualClaim
  , renderAuthoritySurface
  , roundTripProperty
  ) where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON, ToJSON)
import Data.Maybe (Maybe(..), maybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.IO.Unsafe (unsafePerformIO)
import Prelude (Bool(..), Eq(..), IO, Show, (&&), ($), (++), (==), (>>=), (<>) , not, null, otherwise, pure, id, either, Either(..))

import QxFx0.Types.State.SemanticCommitment
  ( FactualClaimPayload(..)
  , CommitmentOrigin(..)
  , TurnSeq(..)
  )
import QxFx0.Types (ClaimAst(..), GfActTopic(..))
import QxFx0.Runtime.PGF (parseClaimAstGf)

newtype AuthoritySurface = AuthoritySurface
  { unAuthoritySurface :: Text
  }
  deriving stock (Eq, Show, Generic)
  deriving newtype (ToJSON, FromJSON)

emptyAuthoritySurface :: AuthoritySurface
emptyAuthoritySurface = AuthoritySurface ""

isStubAuthoritySurface :: AuthoritySurface -> Bool
isStubAuthoritySurface s = T.null (unAuthoritySurface s)

-- | Parse a rendered authority surface back to a typed factual claim.
--
-- Stage 1: attempt GF-backed parsing via 'parseClaimAstGf' (uses the live
-- @spec\/gf\/QxFx0Syntax.pgf@ grammar). Wraps the IO call with
-- 'unsafePerformIO' — safe because the PGF parser is deterministic and
-- referentially transparent for a fixed grammar file and input string.
--
-- Stage 2: fall back to pattern-matching on the four canonical
-- commitment-statement forms (en\/ru UserIs, en\/ru TopicIs).
--
-- Returns @Nothing@ for non-authority surfaces (local recovery, questions,
-- greetings, etc.).
{-# NOINLINE parseAuthoritySurface #-}
parseAuthoritySurface :: AuthoritySurface -> Maybe FactualClaimPayload
parseAuthoritySurface s@(AuthoritySurface txt)
  | T.null (T.strip txt) = Nothing
  | otherwise =
      -- Stage 1: GF-backed parse (real bidirectional parser, F-11)
      let gfResult = unsafePerformIO (parseClaimAstGf Nothing txt)
      in case gfResult of
           Right ast -> Just (claimAstToFactualClaim txt ast)
           Left _    -> parseAuthoritySurfacePattern s

-- | IO variant for contexts where IO is available (preferred over the
-- unsafePerformIO wrapper when possible).
parseAuthoritySurfaceIO :: AuthoritySurface -> IO (Maybe FactualClaimPayload)
parseAuthoritySurfaceIO (AuthoritySurface txt)
  | T.null (T.strip txt) = pure Nothing
  | otherwise = do
      result <- parseClaimAstGf Nothing txt
      case result of
        Right ast -> pure (Just (claimAstToFactualClaim txt ast))
        Left _    -> pure (parseAuthoritySurfacePattern (AuthoritySurface txt))

-- | Convert a parsed 'ClaimAst' to a 'FactualClaimPayload'.
-- The @fcpStatement@ is the original surface text; the @fcpOrigin@ records
-- that the GF parser produced this claim.
claimAstToFactualClaim :: Text -> ClaimAst -> FactualClaimPayload
claimAstToFactualClaim surface ast =
  FactualClaimPayload
    { fcpStatement  = surface
    , fcpConfidence = 0.90
    , fcpOrigin     = OriginParser ("gf:pgf2:" <> claimAstTag ast)
    , fcpTurnSeq    = TurnSeq 0
    , fcpDeps       = []
    }
  where
    claimAstTag (MoveGround _)          = "ground"
    claimAstTag (MoveDefine _ _ _)      = "define"
    claimAstTag (MoveContact _)         = "contact"
    claimAstTag (MoveReflect _)         = "reflect"
    claimAstTag (MoveDescribe _)        = "describe"
    claimAstTag (MoveDeepen _)          = "deepen"
    claimAstTag (MoveConfront _)        = "confront"
    claimAstTag (MoveAnchor _)          = "anchor"
    claimAstTag (MoveClarify _)         = "clarify"
    claimAstTag (MovePurpose _)         = "purpose"
    claimAstTag (MoveHypothesis _)      = "hypothesis"
    claimAstTag (MoveContemplative _)   = "contemplative"
    claimAstTag (MoveCompare _ _)       = "compare"
    claimAstTag (MoveDistinguish _ _)   = "distinguish"
    claimAstTag MoveMisunderstanding    = "misunderstanding"
    claimAstTag (MoveNextStepLocal _)   = "next_step"
    claimAstTag MoveSelfState           = "self_state"
    claimAstTag MoveSystemLogic         = "system_logic"
    claimAstTag MoveOperationalStatus   = "operational_status"
    claimAstTag MoveOperationalCause    = "operational_cause"
    claimAstTag MoveGenerativeThought   = "generative"
    claimAstTag (ClaimPurpose _)        = "claim_purpose"
    claimAstTag ClaimSelfState          = "claim_self"
    claimAstTag (ClaimComparison _ _)   = "claim_compare"
    claimAstTag (MoveInvite _ _ _)      = "invite"
    claimAstTag (MoveCause _ _)         = "cause"
    claimAstTag (MoveActOnTopic ActAnswer)    = "act_on_answer"
    claimAstTag (MoveActOnTopic ActQuestion)  = "act_on_question"
    claimAstTag (MoveActOnTopic ActTopicTerm) = "act_on_topic"
    claimAstTag (MoveActOnTopic ActProject)   = "act_on_project"
    claimAstTag (MoveActOnTopic ActResult)    = "act_on_result"
    claimAstTag (StanceWrapped _ inner) = "stance:" <> claimAstTag inner

-- | Pattern-matching fallback parser for the four canonical
-- commitment-statement forms. Used when the GF parser is unavailable.
parseAuthoritySurfacePattern :: AuthoritySurface -> Maybe FactualClaimPayload
parseAuthoritySurfacePattern (AuthoritySurface txt) =
  let trimmed = T.strip txt
  in parseEnUserRole trimmed
     <|> parseRuUserRole trimmed
     <|> parseEnTopic trimmed
     <|> parseRuTopic trimmed

parseEnUserRole :: Text -> Maybe FactualClaimPayload
parseEnUserRole txt = do
  rest <- T.stripPrefix "User is " txt
  let role = maybe rest id (T.stripSuffix "." rest)
  guard (not (T.null role))
  pure FactualClaimPayload
    { fcpStatement = txt
    , fcpConfidence = 0.95
    , fcpOrigin = OriginParser "en:UserIs"
    , fcpTurnSeq = TurnSeq 0
    , fcpDeps = []
    }

parseRuUserRole :: Text -> Maybe FactualClaimPayload
parseRuUserRole txt = do
  rest <- T.stripPrefix "Пользователь — " txt
  let role = maybe rest id (T.stripSuffix "." rest)
  guard (not (T.null role))
  pure FactualClaimPayload
    { fcpStatement = txt
    , fcpConfidence = 0.95
    , fcpOrigin = OriginParser "ru:UserIs"
    , fcpTurnSeq = TurnSeq 0
    , fcpDeps = []
    }

parseEnTopic :: Text -> Maybe FactualClaimPayload
parseEnTopic txt = do
  rest <- T.stripPrefix "Topic is " txt
  let topic = maybe rest id (T.stripSuffix "." rest)
  guard (not (T.null topic))
  pure FactualClaimPayload
    { fcpStatement = txt
    , fcpConfidence = 0.95
    , fcpOrigin = OriginParser "en:TopicIs"
    , fcpTurnSeq = TurnSeq 0
    , fcpDeps = []
    }

parseRuTopic :: Text -> Maybe FactualClaimPayload
parseRuTopic txt = do
  rest <- T.stripPrefix "Тема — " txt
  let topic = maybe rest id (T.stripSuffix "." rest)
  guard (not (T.null topic))
  pure FactualClaimPayload
    { fcpStatement = txt
    , fcpConfidence = 0.95
    , fcpOrigin = OriginParser "ru:TopicIs"
    , fcpTurnSeq = TurnSeq 0
    , fcpDeps = []
    }

guard :: Bool -> Maybe ()
guard True  = Just ()
guard False = Nothing

-- | Render a factual claim payload as an authority-bearing surface.
renderAuthoritySurface :: FactualClaimPayload -> AuthoritySurface
renderAuthoritySurface payload =
  let originTag = case fcpOrigin payload of
        OriginParser tag -> tag
        _ -> "en:Canonical"
  in AuthoritySurface $ case originTag of
       "en:UserIs" -> "User is " <> renderRole (fcpStatement payload) <> "."
       "ru:UserIs" -> "Пользователь — " <> renderRole (fcpStatement payload) <> "."
       "en:TopicIs" -> "Topic is " <> renderTopic (fcpStatement payload) <> "."
       "ru:TopicIs" -> "Тема — " <> renderTopic (fcpStatement payload) <> "."
       _ -> fcpStatement payload

renderRole :: Text -> Text
renderRole = id

renderTopic :: Text -> Text
renderTopic = id

-- | Round-trip property: parse ∘ render == id on the canonical subset.
roundTripProperty :: FactualClaimPayload -> Bool
roundTripProperty p =
  case parseAuthoritySurface (renderAuthoritySurface p) of
    Just p' -> fcpStatement p == fcpStatement p' && fcpOrigin p == fcpOrigin p'
    Nothing -> False
