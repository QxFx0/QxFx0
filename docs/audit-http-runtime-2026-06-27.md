# D1: Security Audit — scripts/http_runtime.py

## Audit Date: 2026-06-27
## Auditor: Agent2048 (automated)
## File: scripts/http_runtime.py (1172 lines)

## 1. Executive Summary

The HTTP runtime sidecar provides session-affine worker management for the QxFx0
system. It spawns persistent Haskell worker processes via `subprocess.Popen`,
manages session tokens with HMAC-validated claims, and exposes a
`ThreadingHTTPServer` for HTTP endpoints. The overall security posture is
**moderate** — several defensive measures are in place (HMAC token comparison,
session ID validation, input sanitization, loopback bind enforcement), but
there are notable gaps.

## 2. Confirmed Security Posture

### 2.1 Session Token Management (GOOD)
- Tokens are generated using `secrets.token_urlsafe(32)` — cryptographically secure.
- Token comparison uses `hmac.compare_digest()` — constant-time comparison
  prevents timing attacks.
- Token store is persisted as JSON alongside the SQLite DB.
- Token release on session end is implemented (`release_if_matches`).
- Corrupt token stores are handled gracefully (clear + log, not crash).

### 2.2 Session ID Validation (GOOD)
- `SESSION_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")` — strict alphanumeric
  pattern, 128-char limit.
- `validate_session()` is called on all session IDs before use.
- Session IDs are used in subprocess arguments without shell=True — no
  command injection vector.

### 2.3 Input Sanitization (GOOD)
- `sanitize_input(text)` function exists (line 186).
- `INPUT_MAX` enforces a 10000-char limit on input text.
- Rate limiting via `TokenBucket` class (line 168).

### 2.4 Worker Process Isolation (MODERATE)
- Workers are spawned with `subprocess.Popen` using argument lists (no
  `shell=True`) — no shell injection.
- `preexec_fn=os.setpgrp` creates a new process group for each worker —
  allows clean signal handling.
- Worker stderr is pumped to structured JSON logs.
- Protocol version handshake prevents mismatched worker versions.

### 2.5 Bind Address (GOOD)
- `_is_loopback_bind()` checks for 127.0.0.1, localhost, ::1.
- Default bind is loopback only.

## 3. Findings

### F1. Session Token Store Not Encrypted (P3)
**Severity: Low**
The session token store is a plain JSON file at
`{db_path}.http-session-tokens.json`. Any process with read access to the
state directory can extract all active session tokens.

**Recommendation**: Use OS keyring integration or file permissions (0600) on
the token store file. Currently, no explicit `os.chmod` is applied after
writing.

### F2. No CSRF Protection (P3)
**Severity: Low (loopback-only mitigates)**
The HTTP server does not implement CSRF tokens. Since the default bind is
loopback, this is mitigated for local-only deployments. However, if the bind
address is overridden to a non-loopback interface, CSRF becomes exploitable.

**Recommendation**: Add `Origin` or `Referer` header validation. Reject
cross-origin requests when not bound to loopback.

### F3. No Request Body Size Limit Beyond INPUT_MAX (P4)
**Severity: Informational**
While `INPUT_MAX` limits the text content, the HTTP handler does not enforce
a `Content-Length` limit before reading the body. A malicious client could
send a very large body that gets read into memory before validation.

**Recommendation**: Add `Content-Length` header check before reading body.

### F4. Worker Process Lifecycle — No Zombie Reaping (P3)
**Severity: Low**
Worker processes are spawned with `preexec_fn=os.setpgrp` but there is no
explicit `SIGCHLD` handler or `waitpid` call for reaped workers. Dead workers
may become zombies if the `close()` method is not called.

**Recommendation**: Add `os.waitpid(pid, os.WNOHANG)` in the worker close
path, or install a `SIGCHLD` handler.

### F5. No TLS/SSL Support (P4)
**Severity: Informational (loopback mitigates)**
The HTTP server uses plain HTTP. For loopback-only deployments this is
acceptable. For remote deployments, TLS is required.

**Recommendation**: Add optional TLS via `ssl.SSLContext` when bind address
is not loopback.

### F6. Thread Safety of Session Token Store (P3)
**Severity: Low**
The `SessionTokenStore` uses a `threading.Lock()` for claim/validate
operations, but the `_save_tokens` method writes to disk without holding the
lock. Concurrent save operations could overwrite each other.

**Recommendation**: Hold the lock during `_save_tokens` or use atomic write
(write to temp + rename).

## 4. Overall Assessment

The HTTP runtime sidecar is reasonably well-structured for a local-first
deterministic system. The primary security measures (HMAC tokens, session
validation, no shell=True, loopback bind) are sound. The findings are all
low-severity and do not represent immediate exploitation risk for the
designed deployment model (local loopback).

**Risk Level: MODERATE** — suitable for local-first deployment. Not suitable
for network-exposed deployment without addressing F1, F2, and F5.

**Recommendation**: No blocking action required for release. Schedule F1
(file permissions) and F4 (zombie reaping) as follow-up hardening items.
