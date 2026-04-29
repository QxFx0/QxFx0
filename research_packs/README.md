# QxFx0 Research Packs

These files are curated upload-ready packs for external deep research when uploading the whole repository is impractical.

Recommended usage:

1. Start with `research_pack_qxfx0.md` for overall context.
2. Then upload one focused pack:
   - `research_pack_trace.md`
   - `research_pack_shadow.md`
   - `research_pack_decision.md`
   - `research_pack_narrative.md`
3. Ask the model to stay repo-grounded and not invent missing mechanisms.

Current repo snapshot reflected in these packs:

- Date: `2026-04-22`
- Project: `QxFx0`
- Verified recently:
  - `bash scripts/verify.sh` -> `PASS`
  - `bash scripts/release-smoke.sh` -> `PASS`
  - `cabal test qxfx0-test` -> `PASS`
  - `python3 scripts/verify_agda_sync.py` -> `PASS`

Important framing:

- QxFx0 already has a strong architecture.
- The main task is to make declared mechanisms fully operational and verifiable.
- The right question is usually not "what architecture should exist?" but "what is already operational, what is spec-only, and what still lacks parity/tests/diagnostics?"

Companion file:

- `brain_kb2.txt` is a research corpus with design hypotheses and audit meta-models.
- It is useful as a hypothesis bank, not as authoritative evidence of current runtime behavior.
