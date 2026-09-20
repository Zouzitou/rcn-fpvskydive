import json
from dataclasses import asdict
from pathlib import Path
from .mapping import AxisConfig

DEFAULT_MODE = "mode2"

def default_config():
    return {"transmitter_mode": DEFAULT_MODE, "axes": {name: asdict(AxisConfig()) for name in ("left_x", "left_y", "right_x", "right_y")}}

def load_config(root: Path):
    path = root / "state" / "config.json"
    if not path.exists(): return default_config()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        merged = default_config(); merged.update({k: v for k, v in data.items() if k in ("transmitter_mode", "axes")})
        return merged
    except (OSError, ValueError): return default_config()

def save_config(root: Path, config):
    path = root / "state" / "config.json"; path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return path
