# ADR-0021 (proposed): Promote External LLM Transport

- **Status**: Proposed (closure-phase follow-up F-14, Package 10
  acceptance criteria §4)
- **Date**: 2026-06-02
- **Refines**:
  - [ADR-0034 — Self/Core role split](./0034-self-core-role-split.md) §3
    Rule 5 (only `Bridge.ExternalLLM` may be opt-in by feature flag)
  - `docs/closure/PYTHON_STATUS_LEDGER.md` (active Python
    `services/morphology/server.py` → Haskell replacement)
- **Related**:
  - `docs/closure/AUTHORITY_MAP.md §6` (External LLM transport row)
  - `docs/closure/REPLAY_GATE_TRIAGE.md §2.12`
    (AuthoritySurface stub, P4 work)

## 1. Context

`Bridge.ExternalLLM` is the only authority-bearing supplier
that is opt-in by feature flag (per ADR-0034 §3 Rule 5).
The flag (`QXFX0_LLM_TRANSPORT` or similar) is **off** by
default; the runtime is local-first and deterministic
(per AGENTS.md "Decision and response generation are
local-first and deterministic").

Promotion of the flag is a **release event** that requires:

- Provider keys provisioned (real LLM API credentials,
  not test fixtures).
- Rate-limit discipline (per ADR-0010 / -0011 conventions
  on the supplier side).
- Cost gates (per-call and per-session budgets).
- Replay-trace discipline for LLM calls (per Package 3
  the trace must record which calls were made, with what
  prompt hash, with what response, with what cost).

This ADR commits to those criteria and to the
operational discipline that the runtime is **never**
LLM-only; the LLM transport is an opt-in **supplier**,
not a replacement for the local-first path.

## 2. Decision

### 2.1 The promotion gate

The flag flips from `off` to `on` only when **all four**
of the following hold:

- **G1 — provider keys**: at least one provider key is
  provisioned in the deployment environment; the key
  passes the `QXFX0_LLM_TRANSPORT_KEY` validation
  (length, format); the key is **not** logged or
  persisted to the trace.
- **G2 — rate limits**: the rate limiter is in place
  (per-minute, per-hour, per-day); the limiter's
  thresholds are in `docs/closure/CALIBRATION_REPORT.md`.
- **G3 — cost gates**: the per-call cost is bounded
  (e.g. $0.01); the per-session budget is bounded
  (e.g. $1.00); the budgets are part of the
  `Bridge.ExternalLLM` config and the trace records
  the running total.
- **G4 — replay-trace discipline**: the
  `trcLLMCall` trace field is landed; the field carries
  the prompt hash (not the prompt), the response hash
  (not the response), the cost, the rate-limit state,
  and the provider's response time. The field is
  serializable; the round-trip is total.

### 2.2 The release event

When G1–G4 are met, the next release:

1. Changes the default in
   `QxFx0.Bridge.ExternalLLM.parseTransportConfig` (or
   equivalent) from `off` to `on`.
2. Adds a changelog entry under the "Flag flips" section.
3. Updates `docs/closure/AUTHORITY_MAP.md §6` to mark
   the External LLM transport as `production-flag-on`.
4. The `AuthoritySurface` stub (per F-11) is extended
   to a real surface; the GF round-trip is the
   `trcAuthoritySurface` field.

### 2.3 The operational discipline

- **The runtime is never LLM-only.** The local-first path
  is always present; the LLM transport is a **supplier**,
  not a replacement. A misfire in the LLM transport must
  not cascade to the local path.
- **The provider key is never logged or persisted.** The
  trace records a **key fingerprint** (first 8 chars of
  SHA-256 of the key), not the key itself.
- **The cost gates are hard.** A call that would exceed
  the per-call or per-session budget is **rejected**,
  not retried. The rejection is part of the trace.

### 2.4 The Python dependency

`docs/closure/PYTHON_STATUS_LEDGER.md` lists the
`services/morphology/server.py` Python process as the
only active runtime Python. The Haskell replacement is
`QxFx0.Lexicon.Morphology.Parser`. The LLM transport
does **not** depend on this Python process; the LLM
transport is a separate supplier. The Python process
is replaced by the Haskell parser per Package 5, not
by the LLM transport.

## 3. Consequences

### 3.1 Positive

- The system gains an opt-in **supplier** for LLM-driven
  decisions; the local-first path is unchanged.
- The replay-trace discipline (G4) is a hard contract:
  every LLM call is recorded, every response is hashed,
  every cost is bounded.

### 3.2 Negative / risks

- Provider outages cascade to the LLM transport; the
  rate limiter (G2) and the cost gates (G3) mitigate
  but do not eliminate the risk.
- A misconfigured rate limiter can starve the LLM
  transport; the G2 gate is the prerequisite.

### 3.3 Mitigations

- The local-first path is the fallback; the LLM
  transport's failure is recoverable.
- The trace records every call, so a misfire is
  detectable from the trace alone.

## 4. Alternatives considered

- **A1: LLM-only.** Rejected. The local-first path is
  the architectural commitment (per AGENTS.md); LLM-only
  is a regression.
- **A2: Per-call-site opt-in.** Rejected. The flag is
  a single bool; per-call-site is over-engineering.
- **A3: Demote the LLM transport entirely.** Out of
  scope. The transport is part of the supplier
  contract; demoting it is a sister ADR (F-15,
  conditional).

## 5. Acceptance criteria for this ADR

This ADR is **closed** when:

- [ ] G1, G2, G3, G4 are met and recorded.
- [ ] The default is flipped (per §2.2).
- [ ] The release notes include the "Flag flips" entry.
- [ ] `docs/closure/AUTHORITY_MAP.md §6` is updated.
- [ ] The `AuthoritySurface` stub is extended (per F-11
      follow-up).

The ADR is **deferred** until all five criteria are met.
