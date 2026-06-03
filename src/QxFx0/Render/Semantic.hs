{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Render.Semantic
  ( renderSemanticIntrospection
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Types
import QxFx0.Types.TurnProjection (TurnReplayTrace(..))
import QxFx0.Types.Config.Observability
  ( semanticIntrospectionHighLoadThreshold
  , semanticIntrospectionMediumLoadThreshold
  )
import QxFx0.Types.Text (textShow)

renderSemanticIntrospection :: SystemState -> Maybe TurnReplayTrace -> Text
renderSemanticIntrospection ss mTrace =
  let trace = ssTrace ss
      ego = ssEgo ss
      mgEdgeCount = length (mgEdges (ssMeaningGraph ss))
      truthTag = maybe (textShow (ssTruthContractStatus ss)) (textShow . trcTruthContractStatus) mTrace
      authorityTag = maybe "none" (maybe "none" textShow . trcAuthorityClass) mTrace
      assemblyPathTag = maybe "none" (maybe "none" textShow . trcAssemblyPath) mTrace
      replayProvenanceTag = maybe "ReplayProvenanceLegacyIncomplete" (textShow . trcReplayProvenanceStatus) mTrace
      surfaceProvenanceTag = maybe "none" (maybe "none" textShow . trcSurfaceProvenance) mTrace
      contractProvenanceTag = maybe "none" (maybe "none" textShow . trcContractProvenance) mTrace
  in T.unlines
     [ "SEMANTIC_INTROSPECTION_BEGIN"
     , "turn: " <> textShow (ssTurnCount ss)
      , "ema: " <> textShow (atCurrentLoad trace)
      , "register: " <> inferRegisterFromTrace trace
      , "family: " <> textShow (ssLastFamily ss)
      , "focus: " <> ssLastTopic ss
      , "truth_contract: " <> truthTag
      , "authority_class: " <> authorityTag
      , "assembly_path: " <> assemblyPathTag
      , "replay_provenance_status: " <> replayProvenanceTag
      , "surface_provenance: " <> surfaceProvenanceTag
      , "contract_provenance: " <> contractProvenanceTag
      , "governance_runtime_fault: " <> maybe "none" (T.pack . show) (ssGovernanceRuntimeFault ss)
      , "nix: " <> textShow (obsNixCache (ssObservability ss))
      , "ego_agency: " <> textShow (egoAgency ego)
      , "meaning_graph_entries: " <> textShow mgEdgeCount
      , "SEMANTIC_INTROSPECTION_END"
      ]
  where
    inferRegisterFromTrace t
      | atCurrentLoad t > semanticIntrospectionHighLoadThreshold = "\1048\1089\1090\1086\1097\1077\1085\1080\1077"
      | atCurrentLoad t > semanticIntrospectionMediumLoadThreshold = "\1055\1086\1080\1089\1082"
      | otherwise              = "\1053\1077\1081\1090\1088\1072\1083\1100\1085\1086"
