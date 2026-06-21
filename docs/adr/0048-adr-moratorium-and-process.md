# ADR-0048: ADR Moratorium and Process

**Status:** Accepted
**Date:** 2026-06-24
**Supersedes:** None

## Context

The project accumulated +6,787 LOC in one week (Content/ + GeneratedLexicon
subsystem) without any Architecture Decision Record. This is not an isolated
incident — 19 ADRs sat in `proposed/` indefinitely and were never accepted.
The pattern is: code first, document never.

This creates three problems:
1. **Unreviewed architecture** — large subsystems enter production without
   design review or quality gates.
2. **Documentation-code drift** — by the time (if ever) an ADR is written,
   the code has already evolved past the original design.
3. **No accountability** — there is no record of *why* a subsystem was built
   or what alternatives were considered.

## Decision

### Moratorium

**No new code may be merged without an accepted ADR.** This applies to:
- New subsystems or modules (>100 LOC)
- New external dependencies
- Changes to module boundaries or package structure
- New test suites or CI gates
- Changes to the type system (new type families, new Admission types)

### ADR Process

1. **Propose**: Author writes an ADR in `docs/adr/NNNN-title.md` with status
   `Proposed`. The ADR must include: Context, Decision, Alternatives,
   Consequences, Quality Gate.
2. **Review**: At least one reviewer must approve. The review verifies that
   the decision is sound, alternatives were considered, and a quality gate
   is defined.
3. **Accept**: Status changes to `Accepted`. The ADR number is permanent.
4. **Implement**: Code is merged. The ADR number must be referenced in the
   PR description.
5. **Supersede**: If a decision is later reversed, a new ADR with status
   `Accepted` supersedes the old one. The old ADR status changes to
   `Superseded` with a pointer to the replacement.

### CI Enforcement

A CI check (`scripts/check_adr_coverage.sh`) verifies that:
- Every PR touching `src/` or `test/` must reference an accepted ADR number
  in the PR description or commit message.
- ADRs in `docs/adr/` with status `Proposed` for more than 14 days are
  flagged as stale.
- No ADR may be merged with status `Proposed` — it must be `Accepted` or
  `Superseded`.

### Exceptions

- Bug fixes (<20 LOC, no new types or modules): no ADR required.
- Test-only changes (no production code): no ADR required.
- Documentation-only changes: no ADR required.

## Consequences

- **Positive**: Architecture decisions are documented and reviewable.
  Documentation-code drift is reduced. New subsystems have quality gates.
- **Negative**: Merge velocity decreases. Developers must write ADRs before
  code, not after.
- **Mitigation**: ADRs can be short (1-2 pages). The process is lightweight:
  propose, review, accept.

## Quality Gate

This ADR defines its own quality gate: the CI check script
`scripts/check_adr_coverage.sh` must pass on every PR.
