# Contributing to QxFx0

Thanks for contributing.

## Development baseline

1. Use GHC `9.6.6` and Cabal `3.10` (see `flake.nix` and `cabal.project.freeze`).
2. Install Python dependencies:
   `python3 -m pip install -r requirements.txt`
3. Build:
   `cabal build all`

## Required local checks before PR

1. `cabal test qxfx0-test-fast`
2. `bash scripts/check_architecture.sh`
3. `bash scripts/gf_quality_gate.sh`
4. `bash scripts/check_gf_render_path.sh`
5. `bash scripts/check_en_render_path.sh`
6. `bash scripts/check_generated_artifacts.sh`
7. `bash scripts/check_lexicon.sh`
8. `QXFX0_CONTRACT_PROFILE=core bash scripts/ci_gate_contract.sh`

## Scope rules

- Do not bypass architecture boundaries enforced by `scripts/check_architecture.sh`.
- Do not manually edit generated artifacts:
  - `src/QxFx0/Lexicon/Generated.hs`
  - `spec/LexiconData.agda`
  - `spec/LexiconProof.agda`
  - `spec/gf/QxFx0Lexicon*.gf`
  - `spec/gf/lexicon_funmap.tsv`
- Regenerate with scripts and include generator changes in the same PR.

## Commit style

Use small atomic commits with conventional prefixes:

- `fix(...)`
- `feat(...)`
- `chore(...)`
- `docs(...)`
- `test(...)`

## Pull request checklist

- [ ] Branch is up-to-date with `main`
- [ ] Required checks pass locally
- [ ] Docs updated for behavior changes
- [ ] No binary build artifacts committed (`*.o`, `*.hi`, `dist-*`)
