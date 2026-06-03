# QxFx0 Worker Protocol v1

This document specifies the Python sidecar <-> Haskell worker protocol for the
current hardening milestone.

## Transport

- newline-delimited JSON over stdio
- worker process: `qxfx0-main --session-id <sid> --worker-stdio`

## Version

- protocol version: `1`

## Handshake

Sidecar request:

```json
{
  "command": "hello",
  "protocol_version": "1",
  "capabilities": ["health", "state", "turn", "shutdown", "ping", "session_affine"]
}
```

Worker success response:

```json
{
  "status": "ok",
  "command": "hello_ack",
  "message": "hello",
  "protocol_version": "1",
  "protocol_match": true,
  "capabilities": ["health", "state", "turn", "shutdown", "ping", "session_affine"],
  "worker_mode": "persistent_stdio"
}
```

Mismatch response:

```json
{
  "status": "error",
  "error": "protocol_version_mismatch",
  "message": "Unsupported worker protocol version",
  "protocol_version": "1",
  "requested_protocol_version": "...",
  "result_unknown": false,
  "session_valid": true,
  "restart_required": true
}
```

## Canonical Commands

Legacy array commands remain accepted for operational requests:

- `{"command":"hello", ...}`
- `["ping"]`
- `["shutdown"]`
- `["health", "<session_id>"]`
- `["state", "<session_id>"]`
- `["turn", "<session_id>", "dialogue|semantic", "<input>"]`

## Error Taxonomy

Worker protocol errors:

- `malformed_command`
- `unknown_command`
- `unsupported_output_mode`
- `protocol_version_mismatch`

HTTP malformed authenticated request error shape:

```json
{
  "error": "bad_request",
  "error_code": "malformed_authenticated_request",
  "result_unknown": false,
  "session_valid": true,
  "restart_required": false
}
```

## Optional Field Policy

- extra optional fields in the `hello` object are ignored in v1
- legacy array commands do not define optional positional fields

## Session Ownership Contract

- Python sidecar owns the HTTP/session-token perimeter
- Haskell worker owns runtime state and persisted session truth
- a fresh authenticated session claim is rolled back on first-turn failure

## Fixture Set

Implemented fixture coverage for v1:

- handshake success
- version mismatch
- unknown command
- malformed authenticated request
- installed-artifact `--serve-http` smoke outside checkout

Committed fixture artifacts live under:

- `test/fixtures/worker_protocol_v1/`
