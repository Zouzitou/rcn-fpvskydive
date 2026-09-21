from dataclasses import dataclass
from .protocol import StickFrame

def clamp(value, low=-1.0, high=1.0): return max(low, min(high, value))

@dataclass
class AxisConfig:
    invert: bool = False
    center: float = 0.0
    dead_zone: float = 0.03
    saturation: float = 1.0
    exponent: float = 1.0

def map_axis(value: float, config: AxisConfig) -> float:
    value = clamp((value - config.center) / max(config.saturation, 1e-6))
    if abs(value) <= config.dead_zone: value = 0.0
    elif value > 0: value = (value - config.dead_zone) / (1 - config.dead_zone)
    else: value = (value + config.dead_zone) / (1 - config.dead_zone)
    value = (abs(value) ** config.exponent) * (1 if value >= 0 else -1)
    return clamp(-value if config.invert else value)

def normalize_raw(value: int, low=364, center=1024, high=1684) -> float:
    if value <= center: return clamp((value - center) / max(center - low, 1))
    return clamp((value - center) / max(high - center, 1))

def map_sticks(frame: StickFrame, configs=None, transmitter_mode="mode2"):
    """Return Xbox axes using the documented FPV Mode 2 default.

    left vertical=throttle, left horizontal=yaw, right vertical=pitch,
    right horizontal=roll. No buttons are inferred here.
    """
    configs = configs or {name: AxisConfig() for name in ("left_x", "left_y", "right_x", "right_y")}
    if transmitter_mode == "mode1":
        # Mode 1 keeps yaw/roll horizontal but puts throttle on right vertical.
        raw = {"left_x": frame.left_h, "left_y": frame.right_v,
               "right_x": frame.right_h, "right_y": frame.left_v}
    else:
        raw = {"left_x": frame.left_h, "left_y": frame.left_v,
               "right_x": frame.right_h, "right_y": frame.right_v}
    return {name: map_axis(normalize_raw(value), configs[name]) for name, value in raw.items()}
