{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module CLI.Protocol
  ( RuntimeOutputMode(..)
  , WorkerCommand(..)
  , decodeWorkerCommand
  , healthJsonPairs
  , stateJsonPairs
  ) where

import Data.Aeson ((.=))
import Data.Aeson.Types (Pair)
import Data.Text (Text)

import QxFx0.CLI.Parser
  ( RuntimeOutputMode(..)
  , WorkerCommand(..)
  , decodeWorkerCommand
  )
import QxFx0.Render.Text (textShow)

import qualified QxFx0.Runtime as Runtime
import QxFx0.Types.State (ssTurnCount, ssEgo, egoAgency, egoTension, ssLastFamily, ssLastTopic)

healthJsonPairs :: Runtime.SystemHealth -> Text -> Text -> [Pair]
healthJsonPairs health sessionId dbPath =
  [ "status" .= Runtime.shStatus health
  , "runtime_mode" .= Runtime.shRuntimeMode health
  , "ready" .= Runtime.shReady health
  , "db_alive" .= Runtime.shDbAlive health
  , "db_bootstrapable" .= Runtime.shDbBootstrapable health
  , "morpho_ok" .= Runtime.shMorphoReady health
  , "nix_policy_present" .= Runtime.shNixPolicyPresent health
  , "nix_ok" .= Runtime.shNixReady health
  , "nix_issues" .= Runtime.shNixIssues health
  , "embed_ok" .= Runtime.shEmbeddingAlive health
  , "embed_operational" .= Runtime.shEmbeddingOperational health
  , "embed_explicit" .= Runtime.shEmbeddingExplicit health
  , "embed_backend" .= Runtime.shEmbeddingBackend health
  , "embed_quality" .= Runtime.shEmbeddingQuality health
  , "morph_backend" .= Runtime.shMorphBackend health
  , "morph_backend_local" .= Runtime.shMorphBackendLocal health
  , "decision_path_local_only" .= Runtime.shDecisionPathLocalOnly health
  , "network_optional_only" .= Runtime.shNetworkOptionalOnly health
  , "llm_decision_path" .= Runtime.shLlmDecisionPath health
  , "agda_ok" .= Runtime.shAgdaReady health
  , "agda_status" .= Runtime.shAgdaStatus health
  , "agda_witness_path" .= Runtime.shAgdaWitnessPath health
  , "agda_issues" .= Runtime.shAgdaIssues health
  , "datalog_ok" .= Runtime.shDatalogReady health
  , "datalog_issues" .= Runtime.shDatalogIssues health
  , "schema_ok" .= Runtime.shSchemaOk health
  , "schema_version" .= Runtime.shSchemaVersion health
  , "schema_reason" .= Runtime.shSchemaReason health
  , "readiness_mode" .= readinessMode
  , "session_id" .= sessionId
  , "db_path" .= dbPath
  ]
  where
    readinessMode = Runtime.shReadinessMode health

stateJsonPairs :: Runtime.Session -> [Pair]
stateJsonPairs session =
  [ "status" .= ("ok" :: Text)
  , "session_id" .= Runtime.sessSessionId session
  , "state_origin" .= Runtime.sessStateOrigin session
  , "turns" .= ssTurnCount ss
  , "output_mode" .= Runtime.renderRuntimeOutputMode (Runtime.sessOutputMode session)
  , "ego_agency" .= egoAgency (ssEgo ss)
  , "ego_tension" .= egoTension (ssEgo ss)
  , "last_family" .= textShow (ssLastFamily ss)
  , "last_topic" .= ssLastTopic ss
  ]
  where
    ss = Runtime.sessSystemState session
