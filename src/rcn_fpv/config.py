import json
from dataclasses import asdict
from pathlib import Path
from .mapping import AxisConfig

DEFAULT_MODE = "mode2"
AXIS_NAMES = ("left_x", "left_y", "right_x", "right_y")

def default_config():
    return {"transmitter_mode": DEFAULT_MODE, "axes": {name: asdict(AxisConfig()) for name in AXIS_NAMES}}

def load_config(root: Path):
    path = root / "state" / "config.json"
    if not path.exists(): return default_config()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict): return default_config()
        merged = default_config()
        if isinstance(data.get("transmitter_mode"), str): merged["transmitter_mode"] = data["transmitter_mode"]
        if isinstance(data.get("axes"), dict):
            for name in AXIS_NAMES:
                if isinstance(data["axes"].get(name), dict): merged["axes"][name].update(data["axes"][name])
        return merged
    except (OSError, ValueError): return default_config()

def axis_configs(config):
    defaults = asdict(AxisConfig())
    axes = config.get("axes", {}) if isinstance(config, dict) else {}
    axes = axes if isinstance(axes, dict) else {}
    result = {}
    for name in AXIS_NAMES:
        values = axes.get(name, {})
        values = values if isinstance(values, dict) else {}
        try:
            invert = values.get("invert", defaults["invert"])
            result[name] = AxisConfig(
                invert=invert if isinstance(invert, bool) else defaults["invert"],
                center=float(values.get("center", defaults["center"])),
                dead_zone=max(0.0, min(0.99, float(values.get("dead_zone", defaults["dead_zone"])))),
                saturation=max(1e-6, float(values.get("saturation", defaults["saturation"]))),
                exponent=max(0.01, float(values.get("exponent", defaults["exponent"]))),
            )
        except (TypeError, ValueError):
            result[name] = AxisConfig()
    return result

def save_config(root: Path, config):
    path = root / "state" / "config.json"; path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return path
