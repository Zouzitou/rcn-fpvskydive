from dataclasses import dataclass

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
