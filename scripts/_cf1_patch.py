#!/usr/bin/env python3
"""CF-1 patch: Insert WorkerPool and modify SessionRegistry for process pooling."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/home/liskil/my-haskell-project/QxFx0/scripts/http_runtime.py"
with open(path, "r") as f:
    content = f.read()

# 1. Add reassign method to SessionWorker (after turn method)
old_turn = '''    def turn(self, user_input, mode="dialogue"):
        payload = self._request(["turn", self.session_id, mode, user_input])
        runtime_epoch = payload.get("runtime_epoch")
        if isinstance(runtime_epoch, str) and runtime_epoch:
            self.runtime_epoch = runtime_epoch
        return payload'''
new_turn = old_turn + '''

    def reassign(self, new_session_id):
        """Reassign this worker to a new session without respawning."""
        self.session_id = new_session_id'''
content = content.replace(old_turn, new_turn)

# 2. Insert WorkerPool class before SessionRegistry
worker_pool_code = '''

class WorkerPool:
    """Pre-warmed worker pool to reduce per-session spawn latency (CF-1).

    Pre-spawns N SessionWorker instances with pool session IDs at startup.
    When a new session arrives, a pooled worker is reassigned to the real
    session_id, avoiding the fork/exec + Haskell RTS init + handshake cycle.
    If reassignment fails (first turn errors), existing error handling in
    SessionRegistry.dispatch_turn drops the worker and respawns fresh.
    """

    def __init__(self, bin_path, timeout_seconds, pool_size=None):
        self.bin_path = bin_path
        self.timeout_seconds = timeout_seconds
        self.pool_size = max(0, pool_size if pool_size is not None else int(os.environ.get("QXFX0_WORKER_POOL_SIZE", "2")))
        self._lock = threading.Lock()
        self._pool = []
        self._refilling = False
        self._shutdown = False

    def prewarm(self):
        with self._lock:
            while len(self._pool) < self.pool_size and not self._shutdown:
                try:
                    worker = SessionWorker(
                        f"_pool_{len(self._pool)}",
                        self.bin_path,
                        self.timeout_seconds,
                    )
                    self._pool.append(worker)
                    log.info(json.dumps({"event": "pool_worker_prewarmed", "pool_size": len(self._pool)}))
                except Exception as exc:
                    log.warning(json.dumps({"event": "pool_prewarm_failed", "detail": str(exc)[:256]}))
                    break

    def checkout(self):
        with self._lock:
            if self._pool:
                return self._pool.pop(0)
            return None

    def refill_background(self):
        with self._lock:
            if self._refilling or self._shutdown or self.pool_size == 0:
                return
            self._refilling = True
        threading.Thread(target=self._refill, daemon=True).start()

    def _refill(self):
        try:
            self.prewarm()
        finally:
            with self._lock:
                self._refilling = False

    def shutdown(self):
        with self._lock:
            self._shutdown = True
            workers = self._pool
            self._pool = []
        for worker in workers:
            try:
                worker.close(reason="pool_shutdown")
            except Exception:
                pass

    def pool_count(self):
        with self._lock:
            return len(self._pool)

'''
content = content.replace("\nclass SessionRegistry:", worker_pool_code + "class SessionRegistry:")

# 3. Add pool to SessionRegistry.__init__
old_init = '''    def __init__(self, bin_path, ttl_seconds, timeout_seconds, max_sessions):
        self.bin_path = bin_path
        self.ttl_seconds = ttl_seconds
        self.timeout_seconds = timeout_seconds
        self.max_sessions = max(1, int(max_sessions))
        self._lock = threading.Lock()
        self._workers = {}'''
new_init = '''    def __init__(self, bin_path, ttl_seconds, timeout_seconds, max_sessions):
        self.bin_path = bin_path
        self.ttl_seconds = ttl_seconds
        self.timeout_seconds = timeout_seconds
        self.max_sessions = max(1, int(max_sessions))
        self._lock = threading.Lock()
        self._workers = {}
        self._pool = WorkerPool(bin_path, timeout_seconds)'''
content = content.replace(old_init, new_init)

# 4. Modify _get_or_create to try pool first
old_get_or_create = '''    def _get_or_create(self, session_id):
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
            return worker'''
new_get_or_create = '''    def _get_or_create(self, session_id):
        with self._lock:
            self._drop_dead_locked()
            existing = self._workers.get(session_id)
            if existing is not None and existing.is_alive():
                return existing
            if existing is not None and not existing.is_alive():
                self._workers.pop(session_id, None)
            if len(self._workers) >= self.max_sessions:
                raise SessionCapacityError(self.max_sessions, len(self._workers))
            # CF-1: Try pre-warmed pool first to avoid spawn latency
            pooled = self._pool.checkout()
            if pooled is not None and pooled.is_alive():
                pooled.reassign(session_id)
                self._workers[session_id] = pooled
                self._pool.refill_background()
                return pooled
            # Fallback: spawn fresh worker
            worker = SessionWorker(session_id, self.bin_path, self.timeout_seconds)
            self._workers[session_id] = worker
            self._pool.refill_background()
            return worker'''
content = content.replace(old_get_or_create, new_get_or_create)

# 5. Add pool shutdown to SessionRegistry.shutdown
old_shutdown = '''    def shutdown(self):
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
                )'''
new_shutdown = old_shutdown + '''
        self._pool.shutdown()'''
content = content.replace(old_shutdown, new_shutdown)

with open(path, "w") as f:
    f.write(content)
print("CF-1: WorkerPool inserted and _get_or_create modified")
