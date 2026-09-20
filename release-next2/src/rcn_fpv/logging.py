import json
import time
from pathlib import Path

class JsonlLogger:
    def __init__(self, root: Path):
        self.path = root / "logs" / "bridge.jsonl"; self.path.parent.mkdir(parents=True, exist_ok=True)
    def event(self, name, **fields):
        record = {"timestamp": time.time(), "event": name, **fields}
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":")) + "\n")
        return record

def tail(path: Path, count=100):
    if not path.exists(): return []
    return path.read_text(encoding="utf-8", errors="replace").splitlines()[-count:]
