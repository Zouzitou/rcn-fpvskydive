import time
from .bridge import Bridge
from .config import axis_configs, load_config
from .discovery import choose_candidate, enumerate_protocol_ports
from .gamepad import VigemBackend, XboxOutput, self_test
from .runtime import HealthStore, SingletonError
from .transport import SerialTransport

def run(root, interval=0.02):
    backend = VigemBackend()
    result = self_test(backend)
    if not result.passed:
        HealthStore(root).write("failed", virtual_gamepad_test=result.message)
        raise RuntimeError(result.message)
    backend.create()
    output = XboxOutput(backend)
    bridge = Bridge(root, lambda: choose_candidate(enumerate_protocol_ports()), SerialTransport, output, HealthStore(root), axis_configs(load_config(root)))
    try:
        bridge.start()
    except SingletonError:
        try: backend.release()
        except Exception: pass
        HealthStore(root).write("already_running", reason="another bridge instance owns the singleton lock")
        return 0
    try:
        while True:
            if (root / "state" / "stop.request").exists():
                HealthStore(root).write("stopping", reason="operator requested stop")
                return 0
            try: bridge.poll_once()
            except Exception as exc: bridge.disconnect(str(exc))
            time.sleep(interval)
    except KeyboardInterrupt:
        pass
    finally: bridge.stop()

if __name__ == "__main__":
    from pathlib import Path
    root = Path(__import__("os").environ.get("LOCALAPPDATA", Path.home())) / "RCN-FPVSkyDive"
    run(root)
