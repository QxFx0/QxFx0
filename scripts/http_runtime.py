#!/usr/bin/env python3
"""QxFx0 HTTP runtime sidecar with persistent session-affine workers."""

import argparse
import errno
import hmac
import json
import logging
import os
import re
import secrets
import select
import signal
import subprocess
import sys
import threading
import time
from collections import defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


logging.basicConfig(
    level=logging.INFO,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}',
)
log = logging.getLogger("qxfx0.http")

SESSION_RE = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
INPUT_MAX = max(1, int(os.environ.get("QXFX0_HTTP_INPUT_MAX", "10000")))
SESSION_TOKEN_HEADER = "X-QXFX0-Session-Token"


class WorkerPreSendError(Exception):
    """Worker was unavailable before sending command."""


class WorkerPostSendUnknownError(Exception):
    """Command may have been accepted, but final outcome is unknown."""

    def __init__(self, detail, status_code=502):
        super().__init__(detail)
        self.status_code = status_code


class WorkerCommandError(Exception):
    """Worker returned explicit error payload."""

    def __init__(self, payload):
        super().__init__(payload.get("message", "worker returned error"))
        self.payload = payload


class SessionCapacityError(Exception):
    """Session worker registry reached configured capacity."""

    def __init__(self, max_sessions, active_sessions):
        super().__init__(f"session capacity exceeded: active={active_sessions}, max={max_sessions}")
        self.max_sessions = max_sessions
        self.active_sessions = active_sessions


def parse_args():
    parser = argparse.ArgumentParser(description="QxFx0 HTTP runtime sidecar")
    host_default = os.environ.get("QXFX0_HTTP_HOST", os.environ.get("QXFX0_HOST", "127.0.0.1"))
    port_default = os.environ.get("QXFX0_HTTP_PORT", os.environ.get("QXFX0_PORT", "9170"))
    parser.add_argument("--host", default=host_default)
    parser.add_argument("--port", type=int, default=int(port_default))
    parser.add_argument("--bin", dest="bin_path", default=os.environ.get("QXFX0_BIN", "qxfx0-main"))
    parser.add_argument("--workers", type=int, default=int(os.environ.get("QXFX0_WORKERS", "0")))
    parser.add_argument("--api-key", dest="api_key", default=os.environ.get("QXFX0_API_KEY", ""))
    parser.add_argument(
        "--default-session-id",
        default=os.environ.get("QXFX0_DEFAULT_SESSION_ID", ""),
    )
    parser.add_argument(
        "--session-ttl-seconds",
        type=float,
        default=float(os.environ.get("QXFX0_SESSION_TTL_SECONDS", "900")),
    )
    parser.add_argument(
        "--worker-timeout-seconds",
        type=float,
        default=float(os.environ.get("QXFX0_WORKER_TIMEOUT_SECONDS", "12")),
    )
    parser.add_argument(
        "--max-sessions",
        type=int,
        default=int(os.environ.get("QXFX0_MAX_SESSIONS", "128")),
    )
    return parser.parse_args()


ARGS = parse_args()
HOST = ARGS.host
PORT = ARGS.port
API_KEY = ARGS.api_key
DEFAULT_SESSION_ID = ARGS.default_session_id
SESSION_TTL_SECONDS = max(1.0, ARGS.session_ttl_seconds)
WORKER_TIMEOUT_SECONDS = max(1.0, ARGS.worker_timeout_seconds)
MAX_SESSIONS = max(1, ARGS.max_sessions)
LEGACY_WORKERS = ARGS.workers
SESSION_TOKEN_ENFORCED = os.environ.get("QXFX0_REQUIRE_SESSION_TOKEN", "1" if API_KEY else "0") == "1"

READINESS_CACHE_TTL = float(os.environ.get("QXFX0_READINESS_CACHE_TTL", "30"))
_readiness_cache_lock = threading.Lock()
_readiness_cache_payload = None
_readiness_cache_code = None
_readiness_cache_ts = 0.0
_readiness_probe_lock = threading.Lock()


def _is_within_root(candidate, root):
    try:
        return os.path.commonpath([candidate, root]) == root
    except ValueError:
        return False


def resolve_bin_path(raw_path):
    candidate = (raw_path or "").strip()
    if not candidate:
        raise ValueError("empty --bin value")

    has_separator = (os.sep in candidate) or (os.altsep is not None and os.altsep in candidate)
    if not has_separator:
        return candidate

    resolved = os.path.realpath(candidate)
    script_dir = os.path.realpath(os.path.dirname(__file__))
    trusted_roots = [
        os.path.realpath(os.path.join(script_dir, "..")),
        script_dir,
    ]
    explicit_root = os.environ.get("QXFX0_ROOT", "").strip()
    if explicit_root:
        trusted_roots.append(os.path.realpath(explicit_root))

    if not any(_is_within_root(resolved, root) for root in trusted_roots):
        raise ValueError(f"--bin points outside trusted roots: {resolved}")
    if not os.path.isfile(resolved):
        raise ValueError(f"--bin is not a file: {resolved}")
    if not os.access(resolved, os.X_OK):
        raise ValueError(f"--bin is not executable: {resolved}")
    return resolved


try:
    HASKELL_BIN = resolve_bin_path(ARGS.bin_path)
except ValueError as exc:
    log.error(json.dumps({"event": "invalid_bin_path", "error": str(exc)}))
    sys.exit(2)


class TokenBucket:
    def __init__(self, rate=10.0, capacity=30.0):
        self.rate = rate
        self.capacity = capacity
        self.tokens = capacity
        self.last = time.monotonic()

    def consume(self, n=1):
        now = time.monotonic()
        self.tokens = min(self.capacity, self.tokens + (now - self.last) * self.rate)
        self.last = now
        if self.tokens >= n:
            self.tokens -= n
            return True
        return False


rate_limits = defaultdict(lambda: TokenBucket())


def sanitize_input(text):
    if not isinstance(text, str):
        return None
    text = text.strip()
    if not text or len(text) > INPUT_MAX:
        return None
    if re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", text):
        return None
    return text


def resolve_session_token_store_path():
    return f"{resolve_runtime_db_path()}.http-session-tokens.json"


class SessionOwnershipStore:
    def __init__(self, path):
        self.path = path
        self._lock = threading.Lock()
        self._tokens = self._load_tokens()

    def claim_or_validate(self, session_id, presented_token):
        with self._lock:
            expected = self._tokens.get(session_id)
            if expected is None:
                issued = secrets.token_urlsafe(32)
                self._tokens[session_id] = issued
                self._persist_locked()
                return "claimed", issued
            if not presented_token:
                return "missing", None
            if not hmac.compare_digest(str(presented_token), expected):
                return "invalid", None
            return "ok", expected

    def release_if_matches(self, session_id, session_token):
        with self._lock:
            if session_token and self._tokens.get(session_id) == session_token:
                self._tokens.pop(session_id, None)
                self._persist_locked()

    def _load_tokens(self):
        try:
            with open(self.path, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except FileNotFoundError:
            return {}
        except (OSError, ValueError) as exc:
            log.warning(json.dumps({"event": "session_token_store_unreadable", "detail": str(exc)[:256]}))
            return {}
        sessions = payload.get("sessions", {})
        if not isinstance(sessions, dict):
            return {}
        return {
            str(session_id): str(token)
            for session_id, token in sessions.items()
            if validate_session(str(session_id)) and isinstance(token, str) and token
        }

    def _persist_locked(self):
        parent = os.path.dirname(self.path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        tmp_path = f"{self.path}.tmp"
        fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump({"sessions": self._tokens}, handle, ensure_ascii=False, sort_keys=True)
            os.replace(tmp_path, self.path)
        except Exception:
            try:
                os.remove(tmp_path)
            except OSError:
                pass
            raise


def resolve_runtime_db_path():
    explicit = os.environ.get("QXFX0_DB")
    if explicit:
        return explicit
    state_dir = os.environ.get("QXFX0_STATE_DIR")
    if not state_dir:
        xdg_state_home = os.environ.get("XDG_STATE_HOME")
        home = os.environ.get("HOME", ".")
        state_dir = (
            os.path.join(xdg_state_home, "qxfx0")
            if xdg_state_home
            else os.path.join(home, ".local", "state", "qxfx0")
        )
    return os.path.join(state_dir, "qxfx0.db")


def cleanup_probe_db_artifacts(db_path, existed_before):
    if existed_before:
        return
    for suffix in ("", "-wal", "-shm"):
        candidate = f"{db_path}{suffix}"
        try:
            if os.path.exists(candidate):
                os.remove(candidate)
        except OSError:
            pass


def validate_session(session_id):
    return bool(SESSION_RE.match(session_id))


def _is_loopback_bind(host):
    normalized = (host or "").strip().lower()
    return normalized in {"127.0.0.1", "localhost", "::1"}


def classify_bind_error(exc):
    if exc.errno == errno.EADDRINUSE:
        return "port_in_use"
    if exc.errno in (errno.EACCES, errno.EPERM):
        return "bind_permission_denied"
    return "bind_failed"


class SessionWorker:
    def __init__(self, session_id, bin_path, timeout_seconds):
        self.session_id = session_id
        self.bin_path = bin_path
        self.timeout_seconds = timeout_seconds
        self.command_lock = threading.Lock()
        self.last_used_at = time.monotonic()
        self.runtime_epoch = None
        self.process = None
        self._start_process()

    def _start_process(self):
        args = [self.bin_path, "--session-id", self.session_id, "--worker-stdio"]
        self.process = subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            preexec_fn=os.setpgrp,
        )
        threading.Thread(target=self._stderr_pump, daemon=True).start()
        log.info(
            json.dumps(
                {
                    "event": "worker_started",
                    "session": self.session_id,
                    "pid": self.process.pid,
                }
            )
        )

    def _stderr_pump(self):
        if self.process.stderr is None:
            return
        for line in self.process.stderr:
            msg = line.rstrip()
            if msg:
                log.info(
                    json.dumps(
                        {
                            "event": "worker_stderr",
                            "session": self.session_id,
                            "pid": self.process.pid,
                            "line": msg[:500],
                        }
                    )
                )

    def is_alive(self):
        return self.process is not None and self.process.poll() is None

    def close(self, reason):
        if self.process is None:
            return
        with self.command_lock:
            self._shutdown_locked(reason)

    def close_if_idle(self, cutoff_monotonic):
        if self.last_used_at >= cutoff_monotonic:
            return False
        acquired = self.command_lock.acquire(blocking=False)
        if not acquired:
            return False
        try:
            if self.last_used_at >= cutoff_monotonic:
                return False
            self._shutdown_locked("idle_ttl")
            return True
        finally:
            self.command_lock.release()

    def _shutdown_locked(self, reason):
        if self.process is None:
            return
        proc = self.process
        try:
            if proc.poll() is None and proc.stdin is not None:
                proc.stdin.write(json.dumps(["shutdown"]) + "\n")
                proc.stdin.flush()
                self._readline_locked(timeout=1.5)
        except Exception:
            pass
        try:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=2)
        except Exception:
            try:
                proc.kill()
                proc.wait(timeout=1)
            except Exception:
                pass
        self.process = None
        log.info(json.dumps({"event": "worker_stopped", "session": self.session_id, "reason": reason}))

    def turn(self, user_input, mode="dialogue"):
        payload = self._request(["turn", self.session_id, mode, user_input])
        runtime_epoch = payload.get("runtime_epoch")
        if isinstance(runtime_epoch, str) and runtime_epoch:
            self.runtime_epoch = runtime_epoch
        return payload

    def _request(self, command):
        with self.command_lock:
            self.last_used_at = time.monotonic()
            if not self.is_alive():
                raise WorkerPreSendError("worker is not alive before command send")
            assert self.process is not None
            if self.process.stdin is None:
                raise WorkerPreSendError("worker stdin unavailable before command send")
            try:
                self.process.stdin.write(json.dumps(command, ensure_ascii=True) + "\n")
                self.process.stdin.flush()
            except BrokenPipeError as exc:
                self._shutdown_locked("post_send_pipe_closed")
                raise WorkerPostSendUnknownError(
                    "worker pipe closed during command send"
                ) from exc
            except Exception as exc:
                self._shutdown_locked("post_send_transport_error")
                raise WorkerPostSendUnknownError(
                    f"command transport failed after send attempt: {exc}"
                ) from exc
            line = self._readline_locked(self.timeout_seconds)
            if line is None:
                self._shutdown_locked("post_send_no_response")
                raise WorkerPostSendUnknownError(
                    "worker did not return a response after command send",
                    status_code=504,
                )
            line = line.strip()
            if not line:
                self._shutdown_locked("post_send_empty_response")
                raise WorkerPostSendUnknownError(
                    "worker stream closed after command send",
                    status_code=502,
                )
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as exc:
                self._shutdown_locked("post_send_protocol_error")
                raise WorkerPostSendUnknownError(
                    f"invalid worker JSON after command send: {line[:200]}",
                    status_code=502,
                ) from exc
            if payload.get("status") == "error":
                raise WorkerCommandError(payload)
            return payload

    def _readline_locked(self, timeout):
        assert self.process is not None
        if self.process.stdout is None:
            return None
        fd = self.process.stdout.fileno()
        readable, _, _ = select.select([fd], [], [], timeout)
        if not readable:
            return None
        line = self.process.stdout.readline()
        if line == "":
            if self.process.poll() is not None:
                return None
        return line


class SessionRegistry:
    def __init__(self, bin_path, ttl_seconds, timeout_seconds, max_sessions):
        self.bin_path = bin_path
        self.ttl_seconds = ttl_seconds
        self.timeout_seconds = timeout_seconds
        self.max_sessions = max(1, int(max_sessions))
        self._lock = threading.Lock()
        self._workers = {}

    def active_count(self):
        with self._lock:
            self._drop_dead_locked()
            return len(self._workers)

    def dispatch_turn(self, session_id, user_input, mode="dialogue"):
        self.evict_idle()
        try:
            worker = self._get_or_create(session_id)
        except SessionCapacityError as exc:
            return self._session_capacity_exceeded(exc), 503
        try:
            payload = worker.turn(user_input, mode=mode)
            return payload, 200
        except WorkerPreSendError as exc:
            log.warning(
                json.dumps(
                    {
                        "event": "worker_presend_failure",
                        "session": session_id,
                        "detail": str(exc),
                    }
                )
            )
            self._drop_worker(session_id, reason="presend_failure")
            try:
                replacement = self._get_or_create(session_id)
                payload = replacement.turn(user_input, mode=mode)
                return payload, 200
            except SessionCapacityError as retry_exc:
                return self._session_capacity_exceeded(retry_exc), 503
            except WorkerPostSendUnknownError as retry_exc:
                self._drop_worker(session_id, reason="post_send_unknown_after_presend_recovery")
                return self._unknown_turn_result(session_id, retry_exc), retry_exc.status_code
            except WorkerCommandError as retry_exc:
                self._drop_worker(session_id, reason="explicit_worker_error_after_presend_recovery")
                return self._known_worker_error(retry_exc.payload), 502
            except WorkerPreSendError as retry_exc:
                self._drop_worker(session_id, reason="presend_failure_after_retry")
                return self._worker_unavailable(session_id, str(retry_exc)), 502
        except WorkerPostSendUnknownError as exc:
            self._drop_worker(session_id, reason="post_send_unknown")
            return self._unknown_turn_result(session_id, exc), exc.status_code
        except WorkerCommandError as exc:
            self._drop_worker(session_id, reason="explicit_worker_error")
            return self._known_worker_error(exc.payload), 502

    def evict_idle(self):
        cutoff = time.monotonic() - self.ttl_seconds
        with self._lock:
            sessions = list(self._workers.items())
        for session_id, worker in sessions:
            if worker.close_if_idle(cutoff):
                with self._lock:
                    if self._workers.get(session_id) is worker:
                        self._workers.pop(session_id, None)
                log.info(json.dumps({"event": "worker_evicted", "session": session_id}))

    def shutdown(self):
        with self._lock:
            workers = list(self._workers.items())
            self._workers = {}
        for session_id, worker in workers:
            try:
                worker.close(reason="sidecar_shutdown")
            except Exception as exc:
                log.warning(
                    json.dumps(
                        {
                            "event": "worker_shutdown_error",
                            "session": session_id,
                            "detail": str(exc),
                        }
                    )
                )

    def _drop_worker(self, session_id, reason):
        with self._lock:
            worker = self._workers.pop(session_id, None)
        if worker is not None:
            try:
                worker.close(reason=reason)
            except Exception:
                pass

    def _get_or_create(self, session_id):
        with self._lock:
            self._drop_dead_locked()
            existing = self._workers.get(session_id)
            if existing is not None and existing.is_alive():
                return existing
            if existing is not None and not existing.is_alive():
                self._workers.pop(session_id, None)
            if len(self._workers) >= self.max_sessions:
                raise SessionCapacityError(self.max_sessions, len(self._workers))
            worker = SessionWorker(session_id, self.bin_path, self.timeout_seconds)
            self._workers[session_id] = worker
            return worker

    def _drop_dead_locked(self):
        dead = [sid for sid, w in self._workers.items() if not w.is_alive()]
        for sid in dead:
            self._workers.pop(sid, None)
            log.info(json.dumps({"event": "worker_reaped_dead", "session": sid}))

    @staticmethod
    def _unknown_turn_result(session_id, exc):
        del exc
        return {
            "status": "error",
            "error": "turn_outcome_unknown",
            "result_unknown": True,
            "session_id": session_id,
            "detail": "worker outcome unknown after command send",
        }

    @staticmethod
    def _worker_unavailable(session_id, detail):
        del detail
        return {
            "status": "error",
            "error": "worker_unavailable",
            "result_unknown": False,
            "session_id": session_id,
            "detail": "worker unavailable before command execution",
        }

    @staticmethod
    def _known_worker_error(payload):
        return {
            "status": "error",
            "error": payload.get("error", "worker_command_error"),
            "result_unknown": False,
            "detail": "worker rejected turn",
        }

    @staticmethod
    def _session_capacity_exceeded(exc):
        return {
            "status": "error",
            "error": "session_capacity_exceeded",
            "result_unknown": False,
            "detail": str(exc),
            "sessions_active": exc.active_sessions,
            "max_sessions": exc.max_sessions,
        }


registry = SessionRegistry(
    bin_path=HASKELL_BIN,
    ttl_seconds=SESSION_TTL_SECONDS,
    timeout_seconds=WORKER_TIMEOUT_SECONDS,
    max_sessions=MAX_SESSIONS,
)
session_owners = SessionOwnershipStore(resolve_session_token_store_path())

_health_alias_warned = False
_health_alias_warned_lock = threading.Lock()


def _mark_health_alias_warning_once():
    global _health_alias_warned
    with _health_alias_warned_lock:
        if _health_alias_warned:
            return
        _health_alias_warned = True
        log.warning(
            json.dumps(
                {
                    "event": "deprecated_health_alias",
                    "message": "GET /health is deprecated, use /sidecar-health",
                }
            )
        )


def runtime_readiness_probe():
    global _readiness_cache_payload, _readiness_cache_code, _readiness_cache_ts
    now = time.monotonic()
    with _readiness_cache_lock:
        if _readiness_cache_payload is not None and (now - _readiness_cache_ts) < READINESS_CACHE_TTL:
            cached = dict(_readiness_cache_payload)
            cached["from_cache"] = True
            cached["cache_age_seconds"] = round(now - _readiness_cache_ts, 1)
            return cached, _readiness_cache_code
    with _readiness_probe_lock:
        now = time.monotonic()
        with _readiness_cache_lock:
            if _readiness_cache_payload is not None and (now - _readiness_cache_ts) < READINESS_CACHE_TTL:
                cached = dict(_readiness_cache_payload)
                cached["from_cache"] = True
                cached["cache_age_seconds"] = round(now - _readiness_cache_ts, 1)
                return cached, _readiness_cache_code
        args = [HASKELL_BIN, "--runtime-ready"]
        db_path = resolve_runtime_db_path()
        db_existed_before = os.path.exists(db_path)
        try:
            proc = subprocess.Popen(
                args,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                preexec_fn=os.setpgrp,
            )
            try:
                stdout, stderr = proc.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                cleanup_probe_db_artifacts(db_path, db_existed_before)
                return (
                    {
                        "status": "backend_not_ready",
                        "error": "runtime_probe_timeout",
                    },
                    504,
                )
            if proc.returncode != 0:
                log.warning(
                    json.dumps(
                        {
                            "event": "runtime_probe_failed",
                            "rc": proc.returncode,
                            "stderr": stderr.strip()[:512],
                        }
                    )
                )
                cleanup_probe_db_artifacts(db_path, db_existed_before)
                return (
                    {
                        "status": "backend_not_ready",
                        "error": "runtime_probe_failed",
                        "rc": proc.returncode,
                    },
                    503,
                )
            try:
                runtime_health = json.loads(stdout.strip() or "{}")
            except json.JSONDecodeError:
                log.warning(
                    json.dumps(
                        {
                            "event": "runtime_probe_bad_json",
                            "stdout": stdout.strip()[:512],
                        }
                    )
                )
                cleanup_probe_db_artifacts(db_path, db_existed_before)
                return (
                    {
                        "status": "backend_not_ready",
                        "error": "runtime_probe_bad_json",
                    },
                    502,
                )
            ready = bool(runtime_health.get("ready", runtime_health.get("status") == "ok"))
            runtime_status = str(runtime_health.get("status", "ok" if ready else "not_ready"))
            flattened = dict(runtime_health)
            result = (
                {
                    **flattened,
                    "status": runtime_status,
                    "ready": ready,
                    "runtime_status": runtime_status,
                    "runtime_health": runtime_health,
                },
                200 if ready else 503,
            )
            cleanup_probe_db_artifacts(db_path, db_existed_before)
            with _readiness_cache_lock:
                _readiness_cache_payload = result[0]
                _readiness_cache_code = result[1]
                _readiness_cache_ts = time.monotonic()
            return result
        except FileNotFoundError:
            cleanup_probe_db_artifacts(db_path, db_existed_before)
            return (
                {
                    "status": "backend_not_ready",
                    "error": "binary_missing",
                },
                500,
            )
        except Exception as exc:
            log.error(
                json.dumps(
                    {
                        "event": "runtime_probe_internal_error",
                        "detail": str(exc)[:512],
                    }
                )
            )
            cleanup_probe_db_artifacts(db_path, db_existed_before)
            return (
                {
                    "status": "backend_not_ready",
                    "error": "runtime_probe_internal_error",
                },
                500,
            )


class QxFx0Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        log.info(json.dumps({"event": "http", "method": self.command, "path": self.path, "detail": fmt % args}))

    def _send_json(self, data, code=200, extra_headers=None):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if extra_headers:
            for key, value in extra_headers.items():
                self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _check_auth(self):
        if not API_KEY:
            return True
        key = self.headers.get("X-API-Key", "")
        if hmac.compare_digest(key, API_KEY):
            return True
        self._send_json({"error": "unauthorized"}, 401)
        return False

    def _check_rate(self):
        key = self.headers.get("X-API-Key", "anonymous")
        if not rate_limits[key].consume():
            self._send_json({"error": "rate_limited"}, 429)
            return False
        return True

    def do_GET(self):
        parsed = urlsplit(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        if path == "/sidecar-health":
            if API_KEY and not self._check_auth():
                return
            registry.evict_idle()
            sessions_active = registry.active_count()
            self._send_json(
                {
                    "status": "ok",
                    "endpoint": "sidecar-health",
                    "semantics": "sidecar_liveness_only",
                    "sessions_active": sessions_active,
                    "max_sessions": MAX_SESSIONS,
                    "sessions_capacity_remaining": max(0, MAX_SESSIONS - sessions_active),
                    "session_ttl_seconds": SESSION_TTL_SECONDS,
                    "worker_timeout_seconds": WORKER_TIMEOUT_SECONDS,
                },
                200,
            )
            return
        if path == "/health":
            _mark_health_alias_warning_once()
            if API_KEY and not self._check_auth():
                return
            registry.evict_idle()
            sessions_active = registry.active_count()
            self._send_json(
                {
                    "status": "ok",
                    "endpoint": "sidecar-health",
                    "semantics": "sidecar_liveness_only",
                    "deprecated_alias": "/health",
                    "sessions_active": sessions_active,
                    "max_sessions": MAX_SESSIONS,
                    "sessions_capacity_remaining": max(0, MAX_SESSIONS - sessions_active),
                    "session_ttl_seconds": SESSION_TTL_SECONDS,
                    "worker_timeout_seconds": WORKER_TIMEOUT_SECONDS,
                },
                200,
                extra_headers={"X-QXFX0-Deprecated": "use /sidecar-health"},
            )
            return
        if path == "/runtime-ready":
            if not self._check_auth():
                return
            if not self._check_rate():
                return
            session_id_values = query.get("session_id", [])
            session_id = session_id_values[0] if session_id_values else None
            if session_id is not None and not validate_session(session_id):
                self._send_json({"error": "invalid_session"}, 400)
                return
            if session_id is not None:
                self._send_json(
                    {
                        "error": "unsupported_query_param",
                        "param": "session_id",
                        "detail": "/runtime-ready is global and does not accept per-session override",
                    },
                    400,
                )
                return
            payload, code = runtime_readiness_probe()
            payload["endpoint"] = "runtime-ready"
            self._send_json(payload, code)
            return
        self._send_json({"error": "not_found"}, 404)

    def do_POST(self):
        if self.path != "/turn":
            self._send_json({"error": "not_found"}, 404)
            return
        if not self._check_auth():
            return
        if not self._check_rate():
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length <= 0 or length > INPUT_MAX + 512:
                self._send_json({"error": "payload_too_large"}, 413)
                return
            raw = self.rfile.read(length)
            body = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError, ValueError) as exc:
            self._send_json({"error": "bad_request", "detail": str(exc)}, 400)
            return
        session_id = body.get("session_id")
        if session_id is None:
            session_id = DEFAULT_SESSION_ID
        if not session_id:
            self._send_json({"error": "missing_session_id"}, 400)
            return
        user_input = body.get("input", "")
        output_mode = body.get("output_mode", "dialogue")
        if output_mode not in ("dialogue", "semantic"):
            self._send_json({"error": "unsupported_output_mode"}, 400)
            return
        if not validate_session(session_id):
            self._send_json({"error": "invalid_session"}, 400)
            return
        sanitized = sanitize_input(user_input)
        if sanitized is None:
            self._send_json({"error": "invalid_input"}, 400)
            return
        session_token = None
        fresh_claim = False
        if SESSION_TOKEN_ENFORCED:
            presented_session_token = self.headers.get(SESSION_TOKEN_HEADER, "")
            ownership_status, owned_session_token = session_owners.claim_or_validate(session_id, presented_session_token)
            if ownership_status == "missing":
                self._send_json({"error": "session_token_required", "result_unknown": False}, 409)
                return
            if ownership_status == "invalid":
                self._send_json({"error": "invalid_session_token", "result_unknown": False}, 403)
                return
            session_token = owned_session_token
            fresh_claim = ownership_status == "claimed"
        payload, code = registry.dispatch_turn(session_id, sanitized, mode=output_mode)
        if fresh_claim and payload.get("error") == "session_capacity_exceeded":
            session_owners.release_if_matches(session_id, session_token)
            session_token = None
        if session_token is not None and payload.get("error") != "session_capacity_exceeded":
            payload["session_token"] = session_token
        self._send_json(payload, code)


class RuntimeHttpServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


running = True


def graceful_shutdown(signum, frame):
    del frame
    global running
    running = False
    log.info(json.dumps({"event": "shutdown_signal", "signal": signum}))
    registry.shutdown()
    sys.exit(0)


def auto_reap(signum, frame):
    del signum, frame
    try:
        while True:
            pid, _ = os.waitpid(-1, os.WNOHANG)
            if pid <= 0:
                break
    except ChildProcessError:
        return


signal.signal(signal.SIGTERM, graceful_shutdown)
signal.signal(signal.SIGINT, graceful_shutdown)
signal.signal(signal.SIGCHLD, auto_reap)


def main():
    if LEGACY_WORKERS > 0:
        log.info(json.dumps({"event": "legacy_workers_ignored", "workers": LEGACY_WORKERS}))
    allow_non_loopback = os.environ.get("QXFX0_ALLOW_NON_LOOPBACK_HTTP", "0") == "1"
    if not _is_loopback_bind(HOST) and not allow_non_loopback:
        log.error(
            json.dumps(
                {
                    "event": "non_loopback_bind_requires_opt_in",
                    "host": HOST,
                    "detail": "non-loopback HTTP bind requires QXFX0_ALLOW_NON_LOOPBACK_HTTP=1; use reverse proxy for TLS",
                }
            )
        )
        sys.exit(2)
    allow_insecure_no_api_key = os.environ.get("QXFX0_ALLOW_INSECURE_NO_API_KEY", "0") == "1"
    if not API_KEY and not _is_loopback_bind(HOST) and not allow_insecure_no_api_key:
        log.error(
            json.dumps(
                {
                    "event": "api_key_required_for_non_loopback_bind",
                    "host": HOST,
                    "detail": "set QXFX0_API_KEY or bind to loopback; override only with QXFX0_ALLOW_INSECURE_NO_API_KEY=1",
                }
            )
        )
        sys.exit(2)
    try:
        server = RuntimeHttpServer((HOST, PORT), QxFx0Handler)
    except OSError as exc:
        log.error(
            json.dumps(
                {
                    "event": "sidecar_start_failed",
                    "error": classify_bind_error(exc),
                    "host": HOST,
                    "port": PORT,
                    "errno": exc.errno,
                    "detail": str(exc)[:512],
                }
            )
        )
        sys.exit(2)
    log.info(
        json.dumps(
            {
                "event": "start",
                "host": HOST,
                "port": PORT,
                "default_session_id": DEFAULT_SESSION_ID,
                "bin": HASKELL_BIN,
                "session_ttl_seconds": SESSION_TTL_SECONDS,
                "worker_timeout_seconds": WORKER_TIMEOUT_SECONDS,
                "session_token_enforced": SESSION_TOKEN_ENFORCED,
            }
        )
    )
    try:
        while running:
            server.handle_request()
    except Exception as exc:
        log.error(
            json.dumps(
                {
                    "event": "sidecar_runtime_failed",
                    "error": "sidecar_runtime_exception",
                    "detail": str(exc)[:512],
                }
            )
        )
        raise
    finally:
        registry.shutdown()
        server.server_close()
        log.info(json.dumps({"event": "stopped"}))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:
        log.error(
            json.dumps(
                {
                    "event": "sidecar_fatal",
                    "error": "unhandled_exception",
                    "detail": str(exc)[:512],
                }
            )
        )
        sys.exit(1)
