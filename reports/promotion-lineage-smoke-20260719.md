# Promotion V4 Lineage Smoke - 2026-07-19

## Scope

- Database: `~/.local/state/qxfx0/qxfx0.db`.
- Provider env loaded from `~/.config/qxfx0/cerebras.env` without printing secrets.
- Effective transport: existing `mistral` transport pointed at the Cerebras endpoint.
- Stable topic: `свобода`.
- Two separate bounded autonomous sessions, one request per session, retries disabled.
- Production overlay activation was not attempted.

## Request Lineage

- `v4-lineage-smoke-freedom-1`: succeeded; response hash present; 2 `edge_admitted` events and 3 quarantined events.
- `v4-lineage-smoke-freedom-2`: succeeded; different response hash; 0 `edge_admitted` events and 5 quarantined events.
- Both requests have populated `model`, `parser_decision`, `admission_decision`, and `evidence_source` fields.
- The two response hashes differ, while the prompt hashes are the same as expected for the same stable topic.

## Corroboration Result

- Complete admitted canonical shapes with two independent request ids: `0`.
- First request admitted shapes:
  - `свобода | means | independence`
  - `свобода | limited_by | псевдосвобода`
- The second request was locally quarantined against existing runtime endpoint pairs, so its complete lineage cannot count as promotion support.
- Candidate support for v4 draft remains insufficient; no new snapshot, gates, or draft overlay was created.

## Decision

The targeted corroboration smoke failed its intended gate. A bounded broad learning run is intentionally not started. The current runtime admission policy treats equal-authority duplicate endpoint updates as quarantine, so the next step requires a governed corroboration strategy that can produce two independent `runtime_admitted` observations for one canonical candidate shape without manually fabricating evidence or mutating the legacy overlay.

Production DB integrity remains `ok`; the legacy overlay remains `evaluated` and inactive.
