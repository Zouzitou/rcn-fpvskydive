import time
from .bridge import Bridge
from .discovery import choose_candidate, enumerate_protocol_ports
from .gamepad import VigemBackend, XboxOutput, self_test
from .runtime import HealthStore
from .transport import SerialTransport

def run(root, interval=0.1):
    backend = VigemBackend()
    result = self_test(backend)
    if not result.passed:
        HealthStore(root).write("failed", virtual_gamepad_test=result.message)
        raise RuntimeError(result.message)
    backend.create()
    output = XboxOutput(backend)
    bridge = Bridge(root, lambda: choose_candidate(enumerate_protocol_ports()), SerialTransport, output, HealthStore(root))
    bridge.start()
    try:
        while True:
            try: bridge.poll_once()
            except Exception: bridge.disconnect()
            time.sleep(interval)
    except KeyboardInterrupt:
        pass
    finally: bridge.stop()

if __name__ == "__main__":
    from pathlib import Path
    root = Path(__import__("os").environ.get("LOCALAPPDATA", Path.home())) / "RCN-FPVSkyDive"
    run(root)
