# ADR 0002: Local Modeled Embedding Backend

## Status

Proposed

## Context

`QxFx0` currently supports:

- `remote-http`
- `local-deterministic`

`local-deterministic` is operationally useful but semantically weak. It is acceptable for smoke tests and strict offline reproducibility, but it is not a model-backed embedding source and should not be treated as the long-term semantic baseline.

## Decision Drivers

- strict runtime must remain locally reproducible
- the backend should work without external network access
- deployment should remain compatible with Nix and CPU-only environments
- the shell should own model execution behind an explicit embedding backend contract

## Options

### 1. Python sidecar

Pros:

- fastest path to a real local model
- wide model support

Cons:

- adds another service boundary
- weakens the single-runtime story
- complicates process supervision and Nix packaging

### 2. `llama.cpp` or GGUF-compatible runtime

Pros:

- lightweight CPU-first deployment
- mature native runtime
- good fit for deterministic shell-owned handlers

Cons:

- model compatibility and embedding quality must be validated
- packaging weights and native bindings still need design work

### 3. ONNX Runtime

Pros:

- broad model ecosystem
- stable native C API
- clean fit for an explicit shell interpreter

Cons:

- packaging complexity
- runtime and model size need validation in the current deployment contour

## Current Direction

The next evaluation pass should compare:

- `llama.cpp` / GGUF embedding path
- ONNX Runtime C API path

`Python` sidecar remains acceptable as a short-lived prototype path, but not as the target strict default.

## Follow-up

1. Benchmark latency and memory for at least one candidate in each native stack.
2. Choose packaging strategy for model weights.
3. Add a new `LocalModeled` backend to the embedding contract.
4. Remove semantic routing bonuses from `local-deterministic` once `LocalModeled` exists.
