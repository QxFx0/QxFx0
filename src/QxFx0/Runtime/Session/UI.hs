{-# LANGUAGE OverloadedStrings #-}

{-| Human-facing session help and compact state summaries. -}
module QxFx0.Runtime.Session.UI
  ( printHelp
  , printStateSummary
  , governanceSummaryLines
  , governanceAuthorityStatus
  ) where

import Control.Exception (SomeException, finally, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Vector as V
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as T
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Core.MeaningGraph (graphStats)
import QxFx0.Governance.Replay (rebuildGovernedViews)
import QxFx0.Runtime.Session.Types
  ( Session(..)
  , StateOrigin(..)
  , renderRuntimeOutputMode
  )
import QxFx0.Runtime.Wiring (withRuntimeDb)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Self.Field (defaultFieldHeuristics)
import QxFx0.Self.Essence (Essence(..), EssenceCommitment(..), renderEssenceMode)
import QxFx0.Self.Perspective.Reduce (buildActivePerspectiveProjections)
import QxFx0.Self.Salience (defaultSalienceWeights)
import QxFx0.Types.Domain (atCurrentLoad)
import QxFx0.Types.Domain.R5 (R5CoreProfile(..), R5PolicyProfile(..), defaultR5CoreProfile, defaultR5PolicyProfile)
import QxFx0.Types.Observability (KernelPulse(..))
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase(..))
import QxFx0.Types.State.Governance
  ( GovernanceDecision(..)
  , GovernanceEvent(..)
  , GovernanceEventEnvelope(..)
  , GovernanceProjection(..)
  , GovernanceLifecycleStatus(..)
  , GovernanceProvenanceLink(..)
  , GovernedSubject(..)
  , EpistemicStatus(..)
  , renderEpistemicStatus
  , governanceProvenanceTrail
  , governanceHistoryFingerprint
  )
import QxFx0.Types.State
  ( EgoState(..)
  , PerspectiveRegistry(..)
  , SystemState(..)
  , ssGovernanceHistory
  , ssGovernanceProjection
  , ssGovernanceRuntimeFault
  , ssPerspectiveRegistry
  , ssEgo
  , ssEssence
  , ssFieldHeuristics
  , ssKernelPulse
  , ssLastFamily
  , ssLastTopic
  , ssMeaningGraph
  , ssSalienceWeights
  , ssTrace
  , ssTruthContractStatus
  , ssDialoguePhase
  , ssTurnCount
  )

data ReplayTraceSummary = ReplayTraceSummary
  { rtsRecoveryCause :: !(Maybe Text)
  , rtsRecoveryStrategy :: !(Maybe Text)
  , rtsRecoveryEvidence :: ![Text]
  , rtsShadowSeverity :: !(Maybe Text)
  , rtsLearningValidationStatus :: !(Maybe Text)
  , rtsFallbackReason :: !(Maybe Text)
  , rtsAuthorityClass :: !(Maybe Text)
  , rtsTruthContractStatus :: !(Maybe Text)
  , rtsAssemblyPath :: !(Maybe Text)
  , rtsReplayProvenanceStatus :: !(Maybe Text)
  , rtsSurfaceProvenance :: !(Maybe Text)
  , rtsContractProvenance :: !(Maybe Text)
  , rtsDerivationTags :: ![Text]
  , rtsLoadStatus :: !Text
  }

data ReplayTraceLoad
  = ReplayTraceMissing
  | ReplayTraceDbError !Text
  | ReplayTraceDecodeError !Text
  | ReplayTraceSchemaError !Text
  | ReplayTraceLoaded !ReplayTraceSummary

replayTraceLoadStatus :: ReplayTraceLoad -> Text
replayTraceLoadStatus traceLoad =
  case traceLoad of
    ReplayTraceMissing -> "missing"
    ReplayTraceDbError reason -> "db_error:" <> reason
    ReplayTraceDecodeError reason -> "decode_error:" <> reason
    ReplayTraceSchemaError reason -> "schema_error:" <> reason
    ReplayTraceLoaded summary -> rtsLoadStatus summary

replayTraceSummaryMaybe :: ReplayTraceLoad -> Maybe ReplayTraceSummary
replayTraceSummaryMaybe traceLoad =
  case traceLoad of
    ReplayTraceLoaded summary -> Just summary
    _ -> Nothing

printHelp :: IO ()
printHelp = do
  T.putStrLn "Interactive commands:"
  T.putStrLn "  :help      show commands"
  T.putStrLn "  :state     show compact runtime state"
  T.putStrLn "  :dialogue  natural dialogue output"
  T.putStrLn "  :semantic  semantic introspection output"
  T.putStrLn "  :quit      save state and exit"
  T.putStrLn ""
  T.putStrLn "Environment:"
  T.putStrLn "  QXFX0_SESSION_ID    session identifier"
  T.putStrLn "  QXFX0_DB            database path"
  T.putStrLn "  QXFX0_DB_PATH       deprecated alias for QXFX0_DB"
  T.putStrLn "  QXFX0_ROOT          project root"
  T.putStrLn "  QXFX0_RUNTIME_MODE  strict(default)|degraded(test harness only)"
  T.putStrLn "  QXFX0_EMBEDDING_BACKEND  local-deterministic|remote-http"
  T.putStrLn "  QXFX0_SESSION_LOCK  on(default)|off(debug/test only)"

printStateSummary :: Session -> IO ()
printStateSummary session = stateSummaryLines session >>= mapM_ T.putStrLn

governanceSummaryLines :: SystemState -> [Text]
governanceSummaryLines ss =
  let history = ssGovernanceHistory ss
      liveProjection = ssGovernanceProjection ss
      liveRegistry = ssPerspectiveRegistry ss
      rebuildResult = rebuildGovernedViews ss
      latestProvenance = latestGovernanceProvenance history
      (rebuildStatus, summaryProjection, staleCount) =
        case rebuildResult of
          Right (rebuiltRegistry, rebuiltProjection)
            | rebuiltProjection == liveProjection -> ("ok", rebuiltProjection, 0)
            | otherwise ->
                ( "mismatch"
                , rebuiltProjection
                , registryDifferenceCount liveRegistry rebuiltRegistry
                )
          Left _ -> ("unavailable", liveProjection, M.size (prThreads liveRegistry))
  in
    [ "governance_events_count: " <> renderValue (length history)
    , "governance_fingerprint: " <> governanceHistoryFingerprint history
    , "governance_rebuild_status: " <> rebuildStatus
    , "active_perspectives_count: " <> renderValue (length (gpActivePerspectiveProjections summaryProjection))
    , "governed_refs_count: " <> renderValue (length (gpGovernedRefs summaryProjection))
    , "governance_denied_count: " <> renderValue (countGovernanceLifecycle GlsDenied history)
     , "governance_rollback_count: " <> renderValue (countGovernanceLifecycle GlsRolledBack history)
    , "governance_stale_count: " <> renderValue staleCount
    , "governance_freeze_status: " <> governanceFreezeStatus history
    , "governance_authority_status: " <> renderEpistemicStatus (governanceAuthorityStatus ss rebuildStatus)
    , "governance_runtime_fault: " <> maybe "none" (T.pack . show) (ssGovernanceRuntimeFault ss)
    , "latest_governed_subject: " <> maybe "n/a" snd latestProvenance
    , "latest_governance_reason_tag: " <> maybe "n/a" fst latestProvenance
    , "salience_field_contract_status: " <> salienceFieldContractStatus ss
    , "plan_narrative_tone_contract_status: " <> planNarrativeToneContractStatus ss
    , "bayesian_contract_status: " <> bayesianContractStatus ss
    ]

stateSummaryLines :: Session -> IO [Text]
stateSummaryLines session = do
  traceLoad <- loadLatestReplayTrace session
  let ss = sessSystemState session
      latestTrace = replayTraceSummaryMaybe traceLoad
      renderValue :: Show a => a -> Text
      renderValue = T.pack . show
      essenceModeTag =
        case ssEssence ss of
          EssenceUncommitted _ -> "uncommitted"
          EssenceCommitted _ c -> "committed:" <> renderEssenceMode (ecMode c)
      recoveryCauseTag = maybe "n/a" id (rtsRecoveryCause =<< latestTrace)
      recoveryStrategyTag = maybe "n/a" id (rtsRecoveryStrategy =<< latestTrace)
      shadowSeverityTag =
        case rtsShadowSeverity =<< latestTrace of
          Just raw -> raw
          Nothing -> "n/a"
      gradientTag = maybe "n/a" renderGradientTag (latestTrace >>= (parseGradientFromEvidence . rtsRecoveryEvidence))
      truthContractTag = maybe "n/a" id (latestTrace >>= rtsTruthContractStatus)
      authorityClassTag = maybe "n/a" id (latestTrace >>= rtsAuthorityClass)
      assemblyPathTag = maybe "n/a" id (latestTrace >>= rtsAssemblyPath)
      replayProvenanceTag = maybe "n/a" id (latestTrace >>= rtsReplayProvenanceStatus)
      surfaceProvenanceTag = maybe "n/a" id (latestTrace >>= rtsSurfaceProvenance)
      contractProvenanceTag = maybe "n/a" id (latestTrace >>= rtsContractProvenance)
      replayTraceLoadTag = replayTraceLoadStatus traceLoad
  pure
    $ [ "STATE_BEGIN"
      , "session_id: " <> sessSessionId session
      , "state_origin: " <> renderStateOrigin (sessStateOrigin session)
      , "turns: " <> renderValue (ssTurnCount ss)
      , "output_mode: " <> renderRuntimeOutputMode (sessOutputMode session)
      , "atom_trace_ema: " <> renderValue (atCurrentLoad (ssTrace ss))
      , "last_family: " <> renderValue (ssLastFamily ss)
      , "last_topic: " <> ssLastTopic ss
      , "ego_agency: " <> renderValue (egoAgency (ssEgo ss))
      , "ego_tension: " <> renderValue (egoTension (ssEgo ss))
      , "meaning_graph: " <> graphStats (ssMeaningGraph ss)
      , "kernel_pulse: " <> renderValue (kpActive (ssKernelPulse ss))
      , "essence_mode: " <> essenceModeTag
      , "recovery_cause: " <> recoveryCauseTag
      , "shadow_severity: " <> shadowSeverityTag
      , "gradient(m,c,t): " <> gradientTag
      , "strategy: " <> recoveryStrategyTag
      , "learning_authority_status: " <> renderEpistemicStatus (learningAuthorityStatus latestTrace)
      , "gf_lexical_authority_status: " <> renderEpistemicStatus (gfLexicalAuthorityStatus latestTrace)
      , "formal_contour_status: " <> renderEpistemicStatus (formalContourStatus latestTrace)
      , "truth_contract: " <> truthContractTag
      , "authority_class: " <> authorityClassTag
      , "assembly_path: " <> assemblyPathTag
      , "replay_provenance_status: " <> replayProvenanceTag
      , "surface_provenance: " <> surfaceProvenanceTag
      , "contract_provenance: " <> contractProvenanceTag
      , "replay_trace_load_status: " <> replayTraceLoadTag
      , "r5_core_version: " <> renderValue (r5cVersionId defaultR5CoreProfile)
      , "r5_policy_version: " <> renderValue (r5pVersionId defaultR5PolicyProfile)
      , "r5_policy_authority_status: " <> renderEpistemicStatus r5PolicyAuthorityStatus
      ] ++ governanceSummaryLines ss ++ ["STATE_END"]

renderStateOrigin :: StateOrigin -> Text
renderStateOrigin FreshOrigin = "fresh"
renderStateOrigin RestoredOrigin = "restored"
renderStateOrigin RecoveredCorruptOrigin = "recovered_corrupt"

salienceFieldContractStatus :: SystemState -> Text
salienceFieldContractStatus ss
  | ssSalienceWeights ss == defaultSalienceWeights && ssFieldHeuristics ss == defaultFieldHeuristics = "persisted_governing_default"
  | otherwise = "persisted_governing_runtime_tuned"

planNarrativeToneContractStatus :: SystemState -> Text
planNarrativeToneContractStatus ss
  | ssDialoguePhase ss `elem` [Clarifying, Repairing, Contesting] = "bounded_causal_contour_runtime_locked"
  | otherwise = "bounded_causal_contour_policy"

bayesianContractStatus :: SystemState -> Text
bayesianContractStatus ss
  | truthContractIsAuthoritative (ssTruthContractStatus ss) = "bounded_causal_contour_runtime_authoritative"
  | otherwise = "bounded_causal_contour_runtime_capped"

countGovernanceLifecycle :: GovernanceLifecycleStatus -> [GovernanceEvent] -> Int
countGovernanceLifecycle lifecycle = length . filter ((== lifecycle) . geeLifecycleStatus . geEnvelope)

registryDifferenceCount :: PerspectiveRegistry -> PerspectiveRegistry -> Int
registryDifferenceCount live rebuilt =
  let liveThreads = prThreads live
      rebuiltThreads = prThreads rebuilt
      scopes = S.union (M.keysSet liveThreads) (M.keysSet rebuiltThreads)
  in length [ () | scope <- S.toList scopes, M.lookup scope liveThreads /= M.lookup scope rebuiltThreads ]

governanceFreezeStatus :: [GovernanceEvent] -> Text
governanceFreezeStatus history =
  case [ event | event <- reverse history, isFreezeEvent event ] of
    [] -> "none"
    event:_ ->
      let envelope = geEnvelope event
      in case (geeLifecycleStatus envelope, geeDecision envelope) of
           (GlsDenied, _) -> "denied"
           (GlsRolledBack, _) -> "released"
           (_, GovFreeze) -> "frozen"
           (_, GovSuspend) -> "released"
           _ -> "active"

latestGovernanceProvenance :: [GovernanceEvent] -> Maybe (Text, Text)
latestGovernanceProvenance history =
  case governanceProvenanceTrail history of
    Right trail -> case reverse trail of
      [] -> Nothing
      link:_ -> Just (gplReasonTag link, renderGovernedSubject (gplSubject link))
    Left _ -> Nothing

renderGovernedSubject :: GovernedSubject -> Text
renderGovernedSubject = T.pack . show

governanceAuthorityStatus :: SystemState -> Text -> EpistemicStatus
governanceAuthorityStatus ss rebuildStatus =
  case (truthContractIsAuthoritative (ssTruthContractStatus ss), ssGovernanceRuntimeFault ss, rebuildStatus) of
    (False, _, _) -> EpstNonAuthoritative
    (True, Just _, _) -> EpstNonAuthoritative
    (True, Nothing, "ok") -> EpstAuthoritative
    (True, Nothing, "mismatch") -> EpstDegraded
    (True, Nothing, _) -> EpstAdvisory

learningAuthorityStatus :: Maybe ReplayTraceSummary -> EpistemicStatus
learningAuthorityStatus latestTrace =
  case latestTrace >>= rtsLearningValidationStatus of
    Nothing -> EpstObservationalOnly
    Just "accept" -> EpstAuthoritative
    Just "not_attempted" -> EpstObservationalOnly
    Just _ -> EpstNonAuthoritative

gfLexicalAuthorityStatus :: Maybe ReplayTraceSummary -> EpistemicStatus
gfLexicalAuthorityStatus latestTrace =
  case latestTrace >>= rtsReplayProvenanceStatus of
    Just "ReplayProvenanceLegacyIncomplete" -> EpstNonAuthoritative
    _ -> case latestTrace >>= rtsTruthContractStatus of
      Just "CanonicalSurfacePreserved" -> EpstAuthoritative
      Just "AssembledSurfacePreserved" -> EpstAdvisory
      Just "CompatibilityShimSurface" -> EpstNonAuthoritative
      Just "DefaultedSurface" -> EpstNonAuthoritative
      Just "GeneratedArtifactSurface" -> EpstNonAuthoritative
      Just "LegacyIncompleteSurface" -> EpstNonAuthoritative
      Just "ExplicitFallbackSurface" -> EpstFallback
      Just "NonExpansiveRecoverySurface" -> EpstDegraded
      _ -> case latestTrace >>= rtsFallbackReason of
        Nothing -> EpstAdvisory
        Just reason
          | "gf_" `T.isPrefixOf` reason -> EpstFallback
          | "en_unstructured_fallback" `T.isPrefixOf` reason -> EpstFallback
          | "ru_unstructured_fallback" `T.isPrefixOf` reason -> EpstFallback
          | otherwise -> EpstAdvisory

formalContourStatus :: Maybe ReplayTraceSummary -> EpistemicStatus
formalContourStatus latestTrace =
  case latestTrace >>= rtsShadowSeverity of
    Nothing -> EpstObservationalOnly
    Just "ShadowSeverityClean" -> EpstAuthoritative
    Just "ShadowSeverityAdvisory" -> EpstAdvisory
    Just "ShadowSeverityUnavailable" -> EpstDegraded
    Just _ -> EpstDegraded

r5PolicyAuthorityStatus :: EpistemicStatus
r5PolicyAuthorityStatus =
  case r5pStrictnessMode defaultR5PolicyProfile of
    "binding_in_strict_only" -> EpstAdvisory
    "strict_enforced" -> EpstAuthoritative
    "degraded" -> EpstDegraded
    _ -> EpstAdvisory

isFreezeEvent :: GovernanceEvent -> Bool
isFreezeEvent event =
  case geeSubject (geEnvelope event) of
    SubjectFreeze _ -> True
    _ -> False

renderValue :: Show a => a -> Text
renderValue = T.pack . show

loadLatestReplayTrace :: Session -> IO ReplayTraceLoad
loadLatestReplayTrace session = do
  result <- try $ withRuntimeDb (sessRuntime session) $ \db -> do
    let sql = "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
    mStmt <- NSQL.prepare db sql
    case mStmt of
      Left err -> pure (ReplayTraceDbError ("prepare_failed:" <> err))
      Right stmt -> do
        result' <- (
          do
            _ <- NSQL.bindText stmt 1 (sessSessionId session)
            hasRow <- NSQL.stepRow stmt
            if not hasRow
              then pure ReplayTraceMissing
              else do
                payload <- NSQL.columnText stmt 0
                pure (decodeReplayTraceSummary payload)
          ) `finally` finalizeQuietly stmt
        pure result'
  pure (either (ReplayTraceDbError . T.pack . show) id (result :: Either SomeException ReplayTraceLoad))
  where
    decodeReplayTraceSummary :: Text -> ReplayTraceLoad
    decodeReplayTraceSummary payload =
      case Aeson.decode (BL.fromStrict (TE.encodeUtf8 payload)) :: Maybe Aeson.Value of
        Just (Aeson.Object obj) ->
          let recoveryCause = decodeScalarField "trcRecoveryCause" obj
              recoveryStrategy = decodeScalarField "trcRecoveryStrategy" obj
              shadowSeverity = decodeScalarField "trcShadowDivergenceSeverity" obj
              evidence = decodeStringArrayField "trcRecoveryEvidence" obj
              learningValidationStatus = decodeScalarField "trcLearningValidationStatus" obj
              fallbackReason = decodeScalarField "trcFallbackReason" obj
              authorityClass = decodeScalarField "trcAuthorityClass" obj
              truthContractStatus = decodeScalarField "trcTruthContractStatus" obj
              assemblyPath = decodeScalarField "trcAssemblyPath" obj
              replayProvenanceStatus =
                case decodeScalarField "trcReplayProvenanceStatus" obj of
                  Just value -> Just value
                  Nothing -> Just "ReplayProvenanceLegacyIncomplete"
              surfaceProvenance = decodeScalarField "trcSurfaceProvenance" obj
              contractProvenance = decodeScalarField "trcContractProvenance" obj
              derivationTags = decodeStringArrayField "trcDerivationTags" obj
            in ReplayTraceLoaded ReplayTraceSummary
                 { rtsRecoveryCause = recoveryCause
                 , rtsRecoveryStrategy = recoveryStrategy
                 , rtsRecoveryEvidence = evidence
                 , rtsShadowSeverity = shadowSeverity
                 , rtsLearningValidationStatus = learningValidationStatus
                 , rtsFallbackReason = fallbackReason
                 , rtsAuthorityClass = authorityClass
                 , rtsTruthContractStatus = truthContractStatus
                 , rtsAssemblyPath = assemblyPath
                 , rtsReplayProvenanceStatus = replayProvenanceStatus
                  , rtsSurfaceProvenance = surfaceProvenance
                  , rtsContractProvenance = contractProvenance
                  , rtsDerivationTags = derivationTags
                  , rtsLoadStatus = "loaded"
                 }
        Just _ -> ReplayTraceSchemaError "replay_trace_not_object"
        Nothing -> ReplayTraceDecodeError "replay_trace_decode_failed"

    decodeScalarField :: Text -> Aeson.Object -> Maybe Text
    decodeScalarField key obj =
      case KM.lookup (K.fromText key) obj of
        Just (Aeson.String t) -> Just t
        Just (Aeson.Number n) -> Just (T.pack (show n))
        Just (Aeson.Bool True) -> Just "true"
        Just (Aeson.Bool False) -> Just "false"
        _ -> Nothing

    decodeStringArrayField :: Text -> Aeson.Object -> [Text]
    decodeStringArrayField key obj =
      case KM.lookup (K.fromText key) obj of
        Just (Aeson.Array arr) ->
          [ t | Aeson.String t <- V.toList arr ]
        _ -> []

finalizeQuietly :: NSQL.Statement -> IO ()
finalizeQuietly stmt = do
  _ <- try (NSQL.finalize stmt) :: IO (Either SomeException ())
  pure ()

parseGradientFromEvidence :: [Text] -> Maybe (Double, Double, Double)
parseGradientFromEvidence evidence =
  let findMarker prefix =
        case [ rest | entry <- evidence, Just rest <- [T.stripPrefix prefix entry] ] of
          rest : _ -> case reads (T.unpack (T.takeWhile (/= ' ') rest)) of
            [(n, _)] -> Just n
            _ -> Nothing
          [] -> Nothing
      m = findMarker "conatus_gradient_m="
      c = findMarker "conatus_gradient_c="
      t = findMarker "conatus_gradient_t="
  in case (m, c, t) of
       (Just m', Just c', Just t') -> Just (m', c', t')
       _ -> Nothing

renderGradientTag :: (Double, Double, Double) -> Text
renderGradientTag (m, c, t) =
  T.concat [ "m=", T.pack (show m), ",c=", T.pack (show c), ",t=", T.pack (show t) ]
