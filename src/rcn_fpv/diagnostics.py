import json, os, platform, re
from pathlib import Path
from .logging import tail
from .steam import find_fpv_skydive, steam_library_roots
from .driver import discover_driver_evidence, validate_driver
from . import __version__

def process_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (TypeError, ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return "inaccessible"

def redact(value):
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, dict):
        return {str(key): redact(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [redact(item) for item in value]
    text = str(value)
    text = re.sub(r"(?i)(C:\\Users\\)[^\\]+", r"\1<user>", text)
    text = re.sub(r"(?i)(LOCALAPPDATA[=: ]+)[^\\\n]+", r"\1<redacted>", text)
    return text

def report(root: Path, extra=None):
    health = root / "state" / "health.json"
    data = {
        "windows": platform.platform(), "architecture": platform.machine(), "pid": os.getpid(), "root": redact(root),
        "installer_runtime_version": __version__,
        "python_environment": {"managed_python_present": (root / ".venv" / "Scripts" / "python.exe").exists()},
        "virtual_gamepad_test": "not-run",
        "usb_devices": [], "driver": "unknown", "protocol_port": None, "serial_open": "not-run",
        "live_frames": "not-run", "fpv_skydive": "not-run", "startup_registration": "unknown",
        "bridge_process": {"pid": None, "alive": "unknown"},
    }
    if health.exists():
        try:
            data["health"] = json.loads(health.read_text(encoding="utf-8"))
            data["bridge_process"]["pid"] = data["health"].get("pid")
            data["virtual_gamepad_test"] = data["health"].get("virtual_gamepad_test", data["virtual_gamepad_test"])
            data["bridge_process"]["alive"] = process_alive(data["bridge_process"]["pid"])
            data["serial_open"] = data["health"].get("serial_open", data["serial_open"])
            data["protocol_port"] = data["health"].get("protocol_port", data["protocol_port"])
            data["live_frames"] = {
                "packet_count": data["health"].get("packet_count", 0),
                "valid_frame_count": data["health"].get("valid_frame_count", 0),
                "last_valid_frame": data["health"].get("last_valid_frame"),
                "live_input_verified": data["health"].get("live_input_verified", False),
            }
        except (OSError, ValueError):
            data["health"] = {"error": "unreadable health file"}
    data["recent_log_lines"] = [redact(line) for line in tail(root / "logs" / "bridge.jsonl")]
    evidence = discover_driver_evidence()
    if evidence:
        valid, reasons = validate_driver(evidence)
        data["driver"] = {"provider": evidence.provider, "version": evidence.version,
                          "valid": valid, "reasons": reasons}
    data["fpv_skydive"] = redact(find_fpv_skydive(steam_library_roots()))
    startup = root / "state" / "startup.json"
    if startup.exists():
        try:
            data["startup_registration"] = json.loads(startup.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data["startup_registration"] = {"error": "unreadable startup state"}
    if extra: data.update({k: redact(v) for k, v in extra.items()})
    return data

def write_report(root: Path, destination: Path, extra=None):
    destination.write_text(json.dumps(report(root, extra), indent=2), encoding="utf-8")
