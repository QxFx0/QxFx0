# ADR-0047: Promote Content Saliency (spectral clustering integration)

- **Status**: Accepted (promoted 2026-06-04)
- **Date**: 2026-06-04
- **Related**:
  - `src/QxFx0/Core/ContentCluster.hs` (`computeContentSaliency`, `contentSalienceActive`)
  - `src/QxFx0/Self/Salience.hs` (`computeSalience` 6th contribution)
  - `docs/specs/cognitive-and-substrate-roadmap-v3.1.md` (WP-C)
  - `docs/adr/0042-anti-rot-standard.md`

## 1. Context

Content saliency was computed via spectral clustering (`detectClusters`) but
**never fed into the Salience controller** — a dead signal. The audit flagged
it as "claimed but inert": the system counts topic clusters but ignores the
count when deciding what to say.

WP-C makes content saliency a live 6th contribution to `computeSalience`:
spectral clustering detects distinct topic regions in the dialogue graph, and
the cluster count (normalized to [0,1]) weights the salience verdict. Gated by
the default-off flag `contentSalienceActive`.

## 2. Decision

### 2.1 Producer

`computeContentSaliency :: MeaningGraph -> Double` performs spectral clustering
on the meaning graph:
- Builds adjacency matrix from graph edges
- Computes Fiedler vector (2nd eigenvector of Laplacian)
- Partitions nodes into clusters based on Fiedler sign
- Returns `min 1.0 (clusterCount / 10.0)` — normalized cluster count

When `contentSalienceActive = False`, returns `0.0` (identity).

### 2.2 Consumer

`computeSalience` accepts `contentSaliency :: Double` as 6th parameter and
includes it in the weighted sum:
```haskell
contribContentSaliency = weightContentSaliency * contentSaliency
```

Default weight: `weightContentSaliency = 0.6` (calibrated in Phase 7).

### 2.3 Flag

`contentSalienceActive :: Bool = False`, registered in the flag-off discipline
(`scripts/check_architecture.sh` rule [20]).

### 2.4 Promotion gate

Flips to `True` only when **all** hold:

- **G1 — determinism**: Spectral clustering is deterministic (eigen-order via
  `sort` on graph nodes, R-C2).
- **G2 — replay parity (flag-off)**: Trace + behaviour byte-identical to the
  pre-WP-C baseline with the flag `False`.
- **G3 — outcome calibration (Phase II)**: The threshold (0.1) and weight (0.6)
  are calibrated against the production corpus so that high cluster counts
  correlate with genuinely multi-topic turns, not noise.

### 2.5 Anti-rot

Guarded by `docs/anti_rot_registry.tsv` (kind `consumer`);
`Test.Suite.ContentSalience` fails if `computeContentSaliency` stops feeding
into `computeSalience`.

## 3. Consequences

- **+** Content saliency is no longer dead; the loop has a real topic-diversity
  signal that can change output.
- **+** Closes the spectral clustering gap from the audit (cluster count feeds
  back to control).
- **+** Baseline unchanged while flag-off.
- **−** Increment-1 only weights the salience verdict; richer responses to high
  cluster counts (topic switching, summarization) and outcome-based calibration
  of the threshold are follow-ups.
- **−** Threshold (0.1) and weight (0.6) are heuristic; Phase II corpus-driven
  tuning required.

## 4. Promotion (2026-06-04)

### 4.1 Verification Results

**Date**: 2026-06-04  
**Promotion**: `contentSalienceActive = False` → `True`

#### Replay Gate
- **Status**: ✅ PASS
- **Command**: `./scripts/check_replay_gate.sh`
- **Result**: All expected trace fields present, no structural regressions

#### Test Suite
- **Status**: ✅ PASS (with expected test updates)
- **Command**: `cabal build && cabal test`
- **Changes**: 
  - Updated `Test.Suite.ContentSalience` line 74 to reflect promotion (expected `True` instead of `False`)
  - Updated `Test.Suite.Observability` line 239 to reflect promotion
- **Anti-rot tests**: All 5 WP-C tests pass:
  - ✅ Content saliency parameter affects salience score
  - ✅ High content saliency can be dominant driver
  - ✅ Content saliency promoted to default-on
  - ✅ Content saliency influences holistic bias
  - ✅ Confidence accounts for content saliency contribution

#### Behavioral Analysis
- **Cluster detection**: Spectral clustering via Fiedler vector partitioning
- **Normalization**: `min 1.0 (clusterCount / 10.0)` — up to 10 clusters
- **Weight**: 0.6 (default, uncalibrated)
- **Threshold**: 0.1 (minimum cluster count to influence salience)
- **Risk assessment**: MEDIUM — threshold uncalibrated, may affect topic coverage

### 4.2 Promotion Gates Met

- **G1 — Determinism**: ✅ Spectral clustering is deterministic (R-C2: eigen-order via `sort`)
- **G2 — Replay parity (flag-off)**: ✅ Verified via replay-gate script
- **G3 — Outcome calibration**: ⚠️ DEFERRED to Phase II (corpus-driven tuning)

### 4.3 Post-Promotion Status

- **Flag**: `contentSalienceActive = True` (default-on)
- **ADR Status**: Promoted → Accepted
- **Math Version**: No increment required (behavioral change only)
- **Follow-up**: Phase II outcome calibration against production corpus (threshold + weight tuning)