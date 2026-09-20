import subprocess
import sys
import time
from pathlib import Path
from .runtime import HealthStore

def run(root: Path, max_restarts=5):
    """Keep the service alive with bounded exponential restart backoff."""
    health = HealthStore(root); failures = 0
    while True:
        try:
            child = subprocess.Popen([sys.executable, "-m", "rcn_fpv.service"])
            health.write("watchdog_running", child_pid=child.pid, restart_count=failures)
            code = child.wait()
        except KeyboardInterrupt:
            return 0
        if code == 0: return 0
        failures += 1
        delay = min(60, 2 ** min(failures, 5))
        health.write("watchdog_backoff", exit_code=code, restart_count=failures, retry_seconds=delay)
        if failures >= max_restarts:
            health.write("failed", reason="watchdog restart limit reached", restart_count=failures)
            return code or 1
        time.sleep(delay)
