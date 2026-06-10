# RECONCILIATION LEDGER — 2026-06-10

Self-contained status of every TZ-1 audit item (A–O).  Grep-verified; do not trust line references.

---

## A — toxicity fail-closed
**Status:** CLOSED  
**Anchor:** commit `4d6b7a3`, `checkToxicity → InvariantBlock`.

## B — predictiveDelta clamp at FromJSON (KnowledgeTree)
**Status:** CLOSED  
**Anchor:** `Learning/KnowledgeTree.hs:109–110` `clampFruitDelta` on both `conatusDelta` and `predictiveDelta` read paths. Grep confirms `clampFruitDelta (-0.35) 0.40` and `(-0.40) 0.50`.

## C — LocalRecoveryCause / LocalRecoveryStrategy round-trip
**Status:** CLOSED  
**Anchor:** `Types/Recovery.hs:56–64` `ToJSON/FromJSON` via `parseRendered` (inverse of `renderLocalRecoveryCause`/`renderLocalRecoveryStrategy`).

## D — TurnReplayTrace FromJSON
**Status:** CLOSED  
**Anchor:** `Types/TurnProjection.hs:378` `deriving anyclass (ToJSON, FromJSON)` on `TurnReplayTrace`. All nested types (`PreActorFailureEvent`, `EffectSnapshot`, `TurnFamilyDerivationStep`, `GenerationAttempt`, `LocalRecoveryCause`, `LocalRecoveryStrategy`, etc.) also have `FromJSON`. No gap.

## E — *Error flat / structured test coverage
**Status:** CLOSED  
**Anchor:** helpers `matchRuntimeInitError` / `matchSQLiteError` / `matchPersistenceError` landed in `RuntimeInfrastructure.hs` and `StatePersistence.hs`; all non-structural-test call sites in `test/` converted to helpers. `TurnPipelineProtocol.hs` was the last flat site — fixed here.

## F — prod diagnosability (category in logs)
**Status:** CLOSED  
**Anchor:** commit `0b5a61c`, `ExceptionPolicy.hs:188–224` `renderQxFx0ExceptionForLog` emits `category=…, detail=<redacted>`.

## G — pure throw → typed bottom at forced site
**Status:** CLOSED  
**Anchor:** `Core/TurnPipeline/Finalize/State.hs:614` `throw (StateInvariantViolation "...")` with `!episodic0` bang-pattern forcing and one-line comment. No `error` or bare `throw` remains on this site.

## H — string-dispatch (== "symbolic"/"shadow"/"user")
**Status:** DEFERRED  
**Anchor:** refactor, not a bug. Verified sites (grep 2026-06-11):
- `Core/TopicDrift/Pressure.hs:188` `dccKind candidate == "symbolic"`
- `Core/TurnPipeline/Route/Effects.hs:107` `label == "shadow"`
- `Core/TurnPlanning/Builders.hs:94,182,355` `ipfSemanticTarget frame == "user"`
- `Render/Dialogue.hs:426` `ipfSemanticTarget frame == "user"`

## I — unsafePerformIO
**Status:** DEFERRED  
**Anchor:** 13 files (not 6). Grep-verified 2026-06-11:
- **Render path:** `Runtime/AuthorityParse.hs:35` `unsafePerformIO (parseClaimAstGf Nothing txt)` — this is the render-path concern.
- **Config-load pattern (intentional, NOINLINE):** `Runtime/PGF.hs:62` `pgfCacheRef`, `Lexicon/PGFStatus.hs:25` `pgfLoadResult`, `Lexicon/GfMap.hs:101` `gfMapLoadResult`, `Self/ConfigLoad.hs:45` `loadConfigOrBuiltin`, `Runtime/Health.hs` (import only), `Core/PipelineIO/Test.hs:80–81` `consciousState`/`intuitionState` MVars, `Resources/Morphology.hs:39` `cachedFormsBySurface`.

## J — (not in TZ-1 resume)
_N/A_

## K — (not in TZ-1 resume)
_N/A_

## L — (not in TZ-1 resume)
_N/A_

## M — (not in TZ-1 resume)
_N/A_

## N — (not in TZ-1 resume)
_N/A_

## O — slow-suite triage
**Status:** PARTIALLY CLOSED (1 of 7 fixed; 6 documented)  
**Anchor:** `qxfx0-test-slow` 135 cases, 7 failures identified (suite timeout at ~20 min; 7 failures before case 52).  
**Raw tally:** 135 cases, 7 failures, 0 errors.  
**Trivial fix applied:** `RuntimeInfrastructure.hs:1459` `minimalBlob` missing optional compatibility fields (`lastGuardReport`, `dreamState`, `intuitionState`, `semanticAnchor`, `lastTurnDecision`) — added to fixture literal.  
**Open / scoped (do not fix on the fly):**
1. `RuntimeInfrastructure.hs:620` — semanticAnchor must survive persisted load; root cause: state loaded as non-authoritative despite `authoritativeGovernedState` fixture.  
2. `RuntimeInfrastructure.hs:884` — semanticAnchor must survive bootstrap restore; same non-authoritative classification issue.  
3. `RuntimeInfrastructure.hs:1346` — missing flake path should be recovered by build materialization; Datalog/Souffle environment fixture issue.  
4. `RuntimeInfrastructure.hs:1705` — second stale writer must fail with state revision conflict; runtime wraps `PersistenceConflict` as `PERSISTENCE_SAVE_FAILED` instead of surfacing `PERSISTENCE_CONFLICT` code.  
5. `RuntimeInfrastructure.hs:1883` — state summary must surface pre-actor failure kind; `PreActorTransportFailure` not present in `stateSummaryLines`.  
6. `RuntimeInfrastructure.hs:1904` — state summary must surface restart-capped status for non-authoritative restore; saved fresh state (`turnCount=0`) treated as `FreshOrigin` by bootstrap, so restart-capped status never rendered.  

---

## Build & arch
- `cabal build all` — clean (warnings only).  
- Unit raw tally: 1217 cases, 0 errors, 1 pre-existing GF failure (unchanged).  
- Integration parity: 0.  
- Arch: `sed 's/\r$//' scripts/check_architecture.sh > scripts/.arch_tmp.sh && bash scripts/.arch_tmp.sh && rm scripts/.arch_tmp.sh` — 0 violations.
