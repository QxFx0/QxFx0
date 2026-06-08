# ADR-0043: Module Rename Campaign (Tier-0 Cognitive Clarity)

- **Status**: Accepted (2026-06-04)
- **Date**: 2026-06-04
- **Related**:
  - `docs/specs/cognitive-wiring-TZ.md` (WP-I)
  - ADR-0042 (anti-rot standard)
  - `audit-comprehensive-2026-06-03.md` (#8 Spectral zero importers)

## 1. Context

The 2026-06 cognitive audit identified module names that systematically mislead:

- `QxFx0.Core.Spectral` — suggests spectral analysis, actually performs Fiedler
  clustering for content saliency
- `QxFx0.Policy.Consciousness` — suggests consciousness model, actually a
  lexicon of string constants (labels/prefixes)
- `QxFx0.Types.Dream` — suggests dream/sleep, actually topic drift under
  pressure
- `Counterfactual` (field in `Self.Field`) — suggests counterfactual reasoning,
  actually parse entropy

These names create false expectations and hinder onboarding. The rename campaign
(WP-I) stratifies candidates by **serialization risk**:

- **Tier-0**: Modules without serialized types — safe rename (compiler-checked)
- **Tier-1**: Serialized record fields/constructors — requires schema migration

## 2. Decision

### 2.1 Tier-0 Execution (Immediate)

**Completed**: `QxFx0.Core.Spectral` → `QxFx0.Core.ContentCluster`

- Renamed module file: `src/QxFx0/Core/Spectral.hs` →
  `src/QxFx0/Core/ContentCluster.hs`
- Updated module declaration: `module QxFx0.Core.ContentCluster`
- Updated 5 import sites:
  - `src/QxFx0/Core/TurnRouting.hs`
  - `src/QxFx0/Core/TurnPipeline/Finalize/Projection.hs`
  - `src/QxFx0/Core/TurnPipeline/Effects.hs`
  - `src/QxFx0/Self/Salience.hs` (Haddock comments)
  - `test/Test/Suite/ContentSalience.hs`
- Updated `qxfx0.cabal` exposed-modules list
- Build successful, zero behavioral change

**Rejected candidates**:

- `Consciousness` — NOT dead code. Active lexicon used by 3 modules
  (`StanceClassifier/Types`, `BackgroundProcess`, `Intuition`). Exports string
  constants like `deepContentGeneralization`, `desireConflictPrefix`,
  `triggerDeepResonance`. Rename would be cosmetic without value.
- `Dream` / `Counterfactual` — Tier-1 (serialized), see §2.2.

### 2.2 Tier-1 Deferral (Requires Schema Migration)

**Deferred to separate ADR**:

- `QxFx0.Types.Dream` → `QxFx0.Types.TopicDrift`
  - `DreamState`, `DreamConfig` are serialized in `SystemState.ssDream`
  - JSON keys: `"dreamState"`, `"r5State"`, `"kernelDrift"`, etc.
  - Requires versioned `fromJSON` migration (Phase-2 machinery)
- `Counterfactual` (field in `Self.Field`) → `ParseEntropy`
  - `fieldCounterfactual :: Counterfactual` serialized in `TurnReplayTrace`
  - JSON key: `"fieldCounterfactual"`
  - Same migration requirement

**Rationale**: Tier-1 renames break replay-gate (golden corpus deserialization)
without schema migration. Cost/benefit unclear until corpus-driven tuning (Phase
II) validates these fields' actual usage.

## 3. Consequences

### 3.1 Positive

- `ContentCluster` name accurately describes Fiedler clustering mechanism
- Import graph now reflects actual functionality
- Future Tier-0 renames follow same pattern (file → imports → cabal → build)

### 3.2 Negative

- Only 1 of 4 candidates was Tier-0 safe
- `Consciousness` name remains misleading but rename cost > benefit (it's a
  lexicon, not a model)
- Tier-1 renames blocked on schema migration infrastructure

### 3.3 Neutral

- Established Tier-0/Tier-1 stratification for future rename campaigns
- Tier-1 work deferred to post-Phase-II when corpus validates field usage

## 4. Compliance

- ✅ Build passes (`cabal build --ghc-options="-Werror"`)
- ✅ Zero behavioral change (rename only)
- ✅ Anti-rot: `ContentCluster` has live consumer (WP-C wired)
- ✅ Governance: Append-only (no state migration)

## 5. Future Work

- Tier-1 ADR when schema migration machinery ready
- Consider `Consciousness` → `RenderLexicon` if lexicon grows beyond current scope
- Document Tier-0/Tier-1 stratification in `CONTRIBUTING.md`