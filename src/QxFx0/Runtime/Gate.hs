{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.Gate
  ( RuntimeGateFailure(..)
  , evaluateBootstrapReadiness
  , evaluateStrictHealth
  , renderBootstrapGateFailure
  , renderTurnGateFailure
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Resources (ReadinessComponent, ReadinessMode(..))
import QxFx0.Runtime.Health (SystemHealth(..))
import QxFx0.Runtime.Mode (RuntimeMode, isStrictRuntimeMode)

data RuntimeGateFailure
  = GateCriticalReadiness ![ReadinessComponent]
  | GateOptionalReadiness ![ReadinessComponent]
  | GateStrictHealth !SystemHealth
  deriving stock (Eq, Show)

evaluateBootstrapReadiness :: RuntimeMode -> ReadinessMode -> Either RuntimeGateFailure ()
evaluateBootstrapReadiness runtimeMode readinessMode =
  case readinessMode of
    NotReady failed ->
      Left (GateCriticalReadiness failed)
    Degraded failed | isStrictRuntimeMode runtimeMode ->
      Left (GateOptionalReadiness failed)
    _ ->
      Right ()

evaluateStrictHealth :: RuntimeMode -> SystemHealth -> Either RuntimeGateFailure ()
evaluateStrictHealth runtimeMode health
  | not (isStrictRuntimeMode runtimeMode) =
      Right ()
  | shReady health && shStatus health == "ok" =
      Right ()
  | otherwise =
      Left (GateStrictHealth health)

renderBootstrapGateFailure :: RuntimeGateFailure -> Text
renderBootstrapGateFailure failure =
  case failure of
    GateCriticalReadiness failed ->
      "System cannot start: critical components unavailable: " <> renderComponents failed
    GateOptionalReadiness failed ->
      "Strict runtime requires all optional resources: " <> renderComponents failed
    GateStrictHealth health ->
      "Strict runtime requires status=ok, got " <> shStatus health <> " [" <> shReadinessMode health <> "]; " <> renderStrictHealthDetail health

renderTurnGateFailure :: RuntimeGateFailure -> Text
renderTurnGateFailure failure =
  case failure of
    GateCriticalReadiness failed ->
      "Turn blocked: critical components unavailable: " <> renderComponents failed
    GateOptionalReadiness failed ->
      "Turn blocked: strict runtime requires all optional resources: " <> renderComponents failed
    GateStrictHealth health ->
      "Turn blocked: strict runtime requires status=ok, got " <> shStatus health <> " [" <> shReadinessMode health <> "]; " <> renderStrictHealthDetail health

renderComponents :: [ReadinessComponent] -> Text
renderComponents = T.pack . show

renderStrictHealthDetail :: SystemHealth -> Text
renderStrictHealthDetail health =
  let components =
        [ "db=" <> T.pack (show (shDbAlive health && shDbBootstrapable health))
        , "schema=" <> T.pack (show (shSchemaOk health)) <> "(v=" <> T.pack (show (shSchemaVersion health)) <> ")"
        , "agda=" <> T.pack (show (shAgdaReady health))
        , "datalog=" <> T.pack (show (shDatalogReady health))
        , "embed=" <> T.pack (show (shEmbeddingAlive health))
        , "decision_local_only=" <> T.pack (show (shDecisionPathLocalOnly health))
        , "network_optional_only=" <> T.pack (show (shNetworkOptionalOnly health))
        , "llm_decision_path=" <> T.pack (show (shLlmDecisionPath health))
        , "morpho=" <> T.pack (show (shMorphoReady health))
        , "morph_backend=" <> shMorphBackend health
        , "nix=" <> T.pack (show (shNixReady health))
            <> "(policy=" <> T.pack (show (shNixPolicyPresent health)) <> ")"
        ]
      issues = concat
        [ if null (shAgdaIssues health) then [] else ["agda_issues=" <> T.intercalate "," (shAgdaIssues health)]
        , if null (shDatalogIssues health) then [] else ["datalog_issues=" <> T.intercalate "," (shDatalogIssues health)]
        , if null (shNixIssues health) then [] else ["nix_issues=" <> T.intercalate "," (shNixIssues health)]
        , if T.null (shSchemaReason health) then [] else ["schema_reason=" <> shSchemaReason health]
        ]
  in T.intercalate "; " (components ++ issues)
