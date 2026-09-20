import json
import os
import time
from pathlib import Path

class SingletonError(RuntimeError): pass

class ProcessLock:
    """Best-effort per-user singleton lock; Windows uses an exclusive lock file."""
    def __init__(self, path: Path): self.path, self.handle = path, None
    def acquire(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        try:
            self.handle = self.path.open("x", encoding="ascii")
            self.handle.write(f"pid={os.getpid()}\nstarted={time.time()}\n")
            self.handle.flush()
            return True
        except FileExistsError:
            raise SingletonError(f"bridge already running ({self.path})")
    def release(self):
        if self.handle:
            self.handle.close(); self.handle = None
            try: self.path.unlink()
            except FileNotFoundError: pass

class HealthStore:
    def __init__(self, root: Path): self.root = root; self.path = root / "state" / "health.json"
    def write(self, state, **details):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"state": state, "pid": os.getpid(), "timestamp": time.time(), **details}
        self.path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        return payload
