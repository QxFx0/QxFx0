# Changelog

All notable changes are documented in this file.

## [Unreleased]

### Added

- Repository governance baseline:
  - `CONTRIBUTING.md`
  - `CODE_OF_CONDUCT.md`
  - `SECURITY.md`
  - `GOVERNANCE.md`
  - `ROADMAP.md`
  - `THIRD_PARTY_NOTICES.md`
  - `requirements.txt`

### Changed

- CI workflow cleanup:
  - removed dev-only push trigger branch
  - removed redundant legacy `build-test` job

### Fixed

- Removed binary script artifacts from repository working tree:
  - `scripts/fuzz_harness.hi`
  - `scripts/fuzz_harness.o`
- Removed deprecated `warnMorphFallback` path from
  `Semantic/Syntax/Combinators`.
- Removed test-only `testRuntimeParadigms` global from public runtime paradigms
  surface.
