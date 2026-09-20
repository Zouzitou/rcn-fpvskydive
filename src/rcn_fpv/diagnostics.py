import json, os, platform, re
from pathlib import Path
from .logging import tail

def redact(value):
    text = str(value)
    text = re.sub(r"(?i)(C:\\Users\\)[^\\]+", r"\1<user>", text)
    text = re.sub(r"(?i)(LOCALAPPDATA[=: ]+)[^\\\n]+", r"\1<redacted>", text)
    return text

def report(root: Path, extra=None):
    health = root / "state" / "health.json"
    data = {"windows": platform.platform(), "architecture": platform.machine(), "pid": os.getpid(), "root": redact(root)}
    if health.exists():
        try:
            data["health"] = json.loads(health.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data["health"] = {"error": "unreadable health file"}
    data["recent_log_lines"] = [redact(line) for line in tail(root / "logs" / "bridge.jsonl")]
    if extra: data.update({k: redact(v) for k, v in extra.items()})
    return data

def write_report(root: Path, destination: Path, extra=None):
    destination.write_text(json.dumps(report(root, extra), indent=2), encoding="utf-8")
