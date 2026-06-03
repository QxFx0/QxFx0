# Fallback Policy Classification
Status: Verified
Front: `fallback-policy classification`

---

## 1. Purpose

This artifact makes major runtime seams explicit enough that local failures,
degradations, compatibility continuations, and observational-only paths no
longer hide policy authority in ad hoc handling.

It answers, seam by seam:

- when the system fails closed
- when it continues in degraded mode
- when it takes a compatibility fallback
- when it is observational-only

This is a policy-classification front, not a broad behavior rewrite.

---

## 2. Policy Class Definitions

### 2.1 Fail-closed

A seam is `fail-closed` when:

- canonical truth does not advance through that seam on failure
- the main outcome may stop or be rejected
- operator-visible state may still continue as diagnostics
- the seam is not allowed to infer success or authority from partial failure

### 2.2 Fail-open degraded

A seam is `fail-open degraded` when:

- canonical truth or runtime continuity may continue
- but with explicitly reduced epistemic / operational strength
- degraded outputs or runtime state may continue
- the seam must not silently claim canonical authority equal to the canonical path

### 2.3 Compatibility fallback

A seam is `compatibility fallback` when:

- the system continues via an alternate tolerated shape, route, or substrate
- continuity is preserved for compatibility reasons
- canonical truth is not thereby upgraded
- output may continue, but authority is marked as shim / fallback / compatibility

### 2.4 Observational-only

A seam is `observational-only` when:

- diagnostics, replay, metrics, warnings, or operator-visible state may change
- canonical truth does not change because of this seam
- runtime outcome authority does not change because of this seam
- the seam may be noisy without carrying authority consequence

---

## 3. Runtime Seam Inventory

This front classifies major seams in:

- prepare
- route
- render
- finalize / commit
- persistence / bootstrap
- sidecar
- PGF / bootstrap substrate

The named seams below are the hot paths that currently fail, degrade,
continue compatibly, or continue observationally.

---

## 4. Seam-To-Policy Classification Table

| seam | code location | trigger | resulting behavior | policy class | authority consequence | output consequence | canonical truth consequence | operator-visible consequence | notes |
|---|---|---|---|---|---|---|---|---|---|
| prepare missing/unexpected embedding result | `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs:66-69,137-138` | no embedding result or unexpected effect shape | local empty embedding used | fail-open degraded | decision path continues with weaker signal | output may still continue normally | no durable truth blocked | not explicit unless traced in replay/effects | now documented inline as degraded continuation |
| prepare missing nix result | `Prepare/Resolve.hs:70-73` | no nix result | `Blocked "nix_guard_missing_request"` default | fail-open degraded | turn continues with blocked guard status | may change route/output via blocked guard | no commit truth by itself | visible through guard/recovery surfaces | not fail-closed in prepare stage |
| prepare missing consciousness result | `Prepare/Resolve.hs:74-77` | absent/unexpected consciousness effect | `initialLoop` default | fail-open degraded | runtime continuity falls back to initial state | output can continue | no direct durable truth change at this seam | mostly hidden unless traced | soft degraded default |
| prepare missing intuition result | `Prepare/Resolve.hs:78-81` | absent/unexpected intuition effect | default posterior + `defaultIntuitiveState` | fail-open degraded | intuition authority reduced to default | output may continue | no direct durable truth change at this seam | mostly hidden unless traced | soft degraded default |
| prepare missing api health result | `Prepare/Resolve.hs:82-85` | absent/unexpected api health effect | `False` default | fail-open degraded | downstream recovery/health-sensitive logic sees unhealthy | output may continue with degraded planning | no direct durable truth change | visible indirectly via degraded plans | conservative degraded default |
| route shadow unavailable / unexpected shadow result | `src/QxFx0/Core/TurnPipeline/Route/Effects.hs:101-117,149-157` | shadow tool unavailable or unexpected result | typed `ShadowUnavailable`, diagnostics, route continues | fail-open degraded | shadow authority removed, not replaced by fake success | output may continue with degraded/advisory route | no durable truth blocked | visible in diagnostics / recovery typing | degraded continuity, not compatibility |
| route Agda verify not ready in strict mode | `Route/Effects.hs:109-115` | `AgdaInvalid` or non-ready verify | throws `AgdaGateError` | fail-closed | R5 proof authority blocks route | no normal output | no turn truth commit | explicit error/failure | strict proof seam |
| route Agda verify not ready outside strict mode | `Route/Effects.hs:114-115` | non-ready verify in degraded mode | warning only, route continues | fail-open degraded | proof authority reduced | output may continue | no direct durable truth change | warning only | degraded local mode |
| render assembly empty fallback to template path | `src/QxFx0/Core/TurnPipeline/Route/Render.hs:203-212` | assembly path yields empty text | uses template artifact with fallback reason | compatibility fallback | render authority downgraded from canonical assembly | output continues | no durable truth change | fallback reason visible | tolerated alternate route |
| render legal lookup miss | `Route/Render.hs:448-453` | legal fact absent | no knowledge fragment | observational-only | no authority change | output just lacks knowledge addendum | no truth change | no special signal beyond absence | inert except surface content |
| render morphology warning | `Route/Render.hs:441-446` | unknown topic lexeme with warn flag | warning logged only | observational-only | no authority change | output unchanged | no truth change | warning emitted | pure observability |
| render local recovery plan / degraded runtime surface | `Route/Render.hs:251-339,497-579` | low legitimacy / degraded runtime / conatus gate etc. | local recovery surface + downgraded authority classes | fail-open degraded | decision continues under explicit lower authority | output changes visibly | no immediate durable truth change until commit | strong operator-visible downgrade | degraded continuity, not compatibility |
| render external action denied / unscheduled | `Route/Render.hs:303-332,466-488` | guardrail deny, no tool, no action, dedup skip | no external query performed; typed trace retained | observational-only for denied/no-action branch; fail-open degraded for planned recovery without action | no external learning authority enters | output may still continue | no truth change directly | trace/replay visible | denial itself is observational policy signal |
| render external query unexpected effect result | `Route/Render.hs:466-475` | result label mismatch | `EqeInvalidResponse "unexpected_effect_result"` | fail-open degraded | external learning path degrades | output continues | later learning application may fail closed or quarantine | trace visible | degraded request side path |
| runtime PGF missing/lang/parse/io failure | `src/QxFx0/Runtime/PGF.hs:78-105` | missing PGF, missing language, parse fail, exception | returns typed `Left`, caller may use shim/fallback surface | compatibility fallback | canonical linguistic authority not claimed | output can continue via shim/fallback surface | no durable truth change | fallback reason may surface via artifact manifest | classic compatibility fallback |
| Russian PGF shim route | `Runtime/PGF.hs:55-59,73-76` | Russian lang path even on PGF success | returns `AuthorityShim` / `RussianCompatShimRoute` | compatibility fallback | output continues but authority explicitly downgraded | output continues | no durable truth change | manifest/fallback visible | success via compatibility shim, not canonical authority |
| precommit semantic introspection env missing | `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs:79-106` | missing env result | introspection disabled | observational-only | no authority change | output may omit introspection | no truth change | operator surface only | pure surface toggle |
| precommit morphology warn env missing | `Finalize/Precommit.hs:94-105` | missing env result | fallback warning disabled | observational-only | no authority change | no output change | no truth change | warning surface absent | pure observability |
| finalize identity rupture / essence rupture | `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs:69-86` | invariant or essence violation before save | throws before persistence | fail-closed | commit blocked | no final committed output | durable truth does not advance | explicit failure | strong fail-closed seam |
| durable save failure / CAS conflict | `Finalize/Commit.hs:88-101`; `Bridge/StatePersistence.hs:96-130,186-196` | tx failure, stale revision, unexpected save result | throws persistence error before runtime commit | fail-closed | authoritative commit blocked | no committed output | durable truth remains previous | explicit diagnostics | core persistence fail-closed seam |
| runtime commit failure with successful recovery | `Finalize/Commit.hs:102-114,196-201` | runtime-only commit fails after durable save | rehydrate from persisted snapshot, warn only | fail-open degraded | durable truth preserved, runtime continuity recovered | output already committed | canonical truth already committed | warning visible | degraded continuation after durable truth |
| runtime commit failure with recovery failure and rollback attempts | `Finalize/Commit.hs:115-134,203-231` | runtime commit + recovery fail | attempt projection rollback then state rollback, else raise failure | fail-closed around authoritative recovery contract | authority tries to restore previous truth or fails explicitly | committed output may be superseded by rollback failure report | durable truth either restored or explicitly left newer | warnings + error | mixed recovery seam but policy is explicit |
| post-commit housekeeping/checkpoint/metrics tail | `Finalize/Commit.hs:135-179,233-253` | checkpoint or metrics tail fails | warning only, committed turn remains committed | observational-only | no authority change | no output reversal | durable truth unchanged | warning only | pure best-effort tail |
| persistence load corrupt state | `src/QxFx0/Bridge/StatePersistence.hs:198-221`; `Runtime/Session/Bootstrap.hs:143-148` | corrupt blob / decode failure | `LoadStateCorrupt`, bootstrap fails closed | fail-closed | restart blocked | no restored output/session | no restart truth admitted | explicit error | SLICE-NA-001 aligned |
| persistence envelope/plain duality | `StatePersistence.hs:396-401` | legacy envelope on read | accepted as tolerated alternate read shape | compatibility fallback | does not by itself confer more authority | no direct output effect | canonical write remains raw `SystemState` | invisible unless audited | hot-path compatibility residue |
| default-heavy restore decode (`semanticConfig`, intuition, legacy fields) | `StatePersistence.hs` decode + `Types` defaults | missing tolerated fields | fills defaults, load continues | compatibility fallback | may alter runtime support state but not canonical authority by implication | output may differ subtly | canonical write shape unchanged | mostly hidden | compatibility residue, not degraded runtime truth |
| bootstrap substrate/resource backfills | `Runtime/Session/Bootstrap.hs:118-133,149-170`; `Bridge/SQLite/Bootstrap.hs` | missing clusters/claims/scenes, resource overlays | merge/backfill/overlay on restored state | compatibility fallback | backfill is not persisted authority | output/runtime may continue with substrate-enriched state | no new durable truth yet until later save | implicit unless documented | already bounded by bootstrap artifact |
| non-authoritative restart demotion | `StatePersistence.hs:386-394` | non-authoritative truth contract on restore | semantic carry restored then stripped from authority path | fail-open degraded | restart continues with capped authority | output/runtime can continue under reduced authority | durable truth loaded but demoted | explicit in restart surfaces | degraded continuity, not compatibility |
| sidecar auth denial | `app/CLI/Http/Runtime.hs` auth checks | missing/wrong API key | 401 unauthorized | fail-closed | request denied | no output except error payload | no truth change | explicit error | perimeter authority seam |
| sidecar rate-limit or sidecar_busy denial | `Http/Runtime.hs` permit/rate gates | concurrency/rate exhausted | 429 response | fail-closed | request denied/delayed | no turn output | no truth change | explicit error | operational admission seam |
| sidecar token ownership failure/corrupt store | `Http/Runtime.hs` token store path | missing/invalid token or store corruption | 409/403/503 explicit | fail-closed | ownership denied | no turn output | no truth change | explicit error | operational authority seam |
| sidecar readiness probe cache/hint | `Http/Runtime.hs` `/runtime-ready` | second call, probe failure, no session side effects | cache continues observationally; probe failure returns non-ready | fail-open degraded for cached non-authoritative observability; fail-closed for denying ready | readiness authority may deny use but does not alter runtime truth | output payload continues | no truth change | explicit response tags | mixed but classifiable |
| sidecar pre-send dead worker retry | `Http/Runtime.hs` worker dispatch | dead worker before turn sent | retry once on replacement worker | fail-open degraded | continuity preserved if retry succeeds | output may still succeed | no truth change yet | implicit to client unless success/failure differs | degraded continuity |
| sidecar post-send unknown outcome | `Http/Runtime.hs` worker turn path | pipe break/timeout/invalid JSON after send | no auto-retry, explicit `turn_outcome_unknown` | fail-closed | result certainty denied | explicit error output | no new truth claimed by sidecar | explicit operator/client error | strong fail-closed outcome-integrity seam |
| sidecar explicit worker command error | `Http/Runtime.hs` worker path | worker returns explicit error | known failure, worker poisoned | fail-closed | request denied | explicit error output | no new truth claimed on failed turn | explicit error | strong worker-integrity seam |
| embedded SQL fallback | `Bridge/SQLite/Bootstrap.hs:141-184` | canonical spec/sql unavailable | fallback only if explicit env opt-in; otherwise startup error | compatibility fallback when opted in; fail-closed by default | schema bootstrap authority stays with canonical spec unless operator opts in | startup may continue only under explicit compatibility path | no truth without bootstrap | explicit if audited/logged | hot-path compatibility residue but tightly gated |

---

## 5. Authority Consequence Map

### 5.1 Can change authoritative truth

Only canonical commit/save seams, and they fail closed on failure:
- durable save path
- rollback restore of previous authoritative state after double failure

All other seams in this front either block, degrade, fallback compatibly, or remain observational.

### 5.2 Can change projection only

- projection rollback / divergence log cleanup in finalize recovery
- render/authority class surfaces and replay manifests

These do not outrank durable authoritative truth.

### 5.3 Can change runtime-only state

- prepare defaults (`initialLoop`, `defaultIntuitiveState`, `apiHealthy=False`)
- runtime commit failure recovery (rehydration)
- sidecar worker lifecycle continuity decisions
- runtime readiness cache

### 5.4 Can change only output/render surface
n
- PGF shim/fallback output
- local recovery banners
- legal-fragment absence
- morphology fallback warnings (warning-only)
- response mapping payloads

### 5.5 Can change only operator-visible observability

- semantic introspection env toggle
- morphology warning env toggle
- post-commit metrics/checkpoint warnings
- readiness cache `from_cache`
- deprecated `/health` alias warning

### 5.6 Entirely inert except for diagnostics

- test marker once-file path failure when not allowed
- health alias warning flag
- various stderr warnings around non-authoritative restore / morphology fallback / post-commit tail

---

## 6. Mixed / Ambiguous Policy Sites

### 6.1 Prepare soft defaults

Location:
- `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs:66-85`

Why mixed:
- several missing effect results collapse into local defaults without an explicit policy artifact in code

Current class:
- fail-open degraded

Safe for now:
- yes; now explicitly commented and grounded by this artifact

Later owner:
- fallback-policy cleanup or prepare-effect hardening front

### 6.2 Runtime readiness endpoint

Location:
- `app/CLI/Http/Runtime.hs` `/runtime-ready`

Why mixed:
- auth, rate limit, cached observational reuse, and backend readiness authority share one path

Current class:
- mixed fail-closed + fail-open degraded + observational-only optimization

Safe for now:
- yes, because the sub-roles are explicit and tested

Later owner:
- readiness/health extraction or dedicated fallback cleanup

### 6.3 Non-authoritative restore path

Location:
- `StatePersistence.loadState` + bootstrap restore

Why mixed:
- restored state continues, but semantic carry is demoted while other continuity state survives

Current class:
- fail-open degraded

Safe for now:
- yes; already bounded by `SLICE-NA-001`

Later owner:
- none in this front; follow taxonomy/restart front if needed

### 6.4 PGF Russian shim route

Location:
- `src/QxFx0/Runtime/PGF.hs:55-59,73-76`

Why mixed:
- successful output is still explicitly non-canonical (`AuthorityShim`)

Current class:
- compatibility fallback

Safe for now:
- yes, but hot-path residue remains

Later owner:
- persistence/PGF compatibility compression or deeper GF cleanup

### 6.5 Finalize runtime-commit recovery path

Location:
- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs:102-138`

Why mixed:
- durable truth is already committed, then runtime continuity may degrade, then rollback may partially restore projections/state

Current class:
- mixed fail-open degraded recovery + fail-closed rollback contract + observational tail

Safe for now:
- yes; the commit-machine front already bounded it

Later owner:
- none here; commit-machine cleanup if simplification is later desired

### 6.6 Embedded SQL fallback

Location:
- `Bridge/SQLite/Bootstrap.hs:141-184`

Why mixed:
- fail-closed by default, compatibility fallback under explicit env opt-in

Current class:
- compatibility fallback (opted-in), otherwise fail-closed

Safe for now:
- yes; explicit opt-in preserves authority clarity

Later owner:
- bounded drift cleanup / compatibility compression

---

## 7. Hot-Path Compatibility Fallback Subset

These are true compatibility-fallback residues, not just degraded runtime handling:

1. `PersistenceEnvelope` vs plain `SystemState` read duality
2. default-heavy restore decode for tolerated legacy fields/config
3. Russian PGF shim route (`AuthorityShim`, `RussianCompatShimRoute`)
4. embedded SQL fallback behind explicit opt-in
5. bootstrap substrate backfill/overlay that continues continuity but is not raw persisted truth

These should be treated as compatibility paths, not canonical success.

---

## 8. Existing Validation Alignment

Existing tests already ground the classified seam behavior:

- persistence/restore/bootstrap policy contours
  - `test/Test/Suite/RuntimeInfrastructure.hs`
- route/finalize recovery and degraded local recovery contours
  - `test/Test/Suite/TurnPipelineProtocol.hs`
- sidecar auth/admission/ownership/readiness/worker failure contours
  - `test/Test/Suite/HttpRuntime.hs`
- non-authoritative restart continuity and degraded first-turn semantics
  - `test/Test/Suite/SemanticSlices.hs`

No new behavior tests were required for this front because the major seam classes are already exercised; the remaining work was to make the policy classes explicit.

---

## 9. Closure Statement

This front is closable because:

- major runtime seams are inventoried
- each seam is assigned one explicit primary policy class
- authority consequences are explicit
- mixed/ambiguous policy sites are named
- hot-path compatibility fallback is identified as such
- later work no longer needs to infer fallback semantics from scattered local code

Bounded next front enabled by this artifact:
- `bounded drift cleanup`

---

## 10. Evidence References

Primary code:
- `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs`
- `src/QxFx0/Core/TurnPipeline/Route/Effects.hs`
- `src/QxFx0/Core/TurnPipeline/Route/Render.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs`
- `src/QxFx0/Bridge/StatePersistence.hs`
- `src/QxFx0/Runtime/Session/Bootstrap.hs`
- `src/QxFx0/Runtime/Wiring/Handlers.hs`
- `src/QxFx0/Runtime/PGF.hs`
- `src/QxFx0/Bridge/SQLite/Bootstrap.hs`
- `app/CLI/Http/Runtime.hs`

Prerequisite artifacts:
- `docs/system_state_taxonomy.md`
- `docs/commit_restore_state_machine.md`
- `docs/bootstrap_lifecycle_boundaries.md`
- `docs/sidecar_control_plane_decomposition.md`

Existing tests used as alignment evidence:
- `test/Test/Suite/RuntimeInfrastructure.hs`
- `test/Test/Suite/TurnPipelineProtocol.hs`
- `test/Test/Suite/HttpRuntime.hs`
- `test/Test/Suite/SemanticSlices.hs`
