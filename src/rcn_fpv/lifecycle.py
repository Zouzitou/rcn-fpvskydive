from dataclasses import dataclass
from enum import Enum
from time import monotonic
from typing import Optional, Set, Tuple

class BridgeState(str, Enum):
    WAITING_FOR_CONTROLLER = "waiting_for_controller"
    OPENING_PROTOCOL = "opening_protocol"
    VERIFYING_LIVE_INPUT = "verifying_live_input"
    CONNECTED = "connected"
    RECONNECT_BACKOFF = "reconnect_backoff"
    FAILED = "failed"

@dataclass
class LiveVerification:
    required_axes: Tuple[str, ...] = ("left_x", "left_y", "right_x", "right_y")
    changed: Optional[Set[str]] = None
    def __post_init__(self):
        if self.changed is None: self.changed = set()
    def observe(self, axis: str, before: float, after: float):
        if axis in self.required_axes and abs(after - before) >= 0.05:
            self.changed.add(axis)
    @property
    def complete(self): return set(self.required_axes) <= self.changed

class Lifecycle:
    def __init__(self, health, backoff_seconds=(1, 2, 5, 10, 30), stability_seconds=10):
        self.health = health; self.state = BridgeState.WAITING_FOR_CONTROLLER
        self.backoff_seconds = tuple(backoff_seconds); self.failures = 0; self.verification = LiveVerification()
        self.last_frame = None; self.stability_seconds = stability_seconds; self.connected_at = None
    def waiting(self):
        self.state = BridgeState.WAITING_FOR_CONTROLLER; self.health.write(self.state.value)
    def candidate_found(self, **details):
        self.verification = LiveVerification()
        self.connected_at = None
        details.setdefault("live_axes", [])
        details.setdefault("live_input_verified", False)
        details.setdefault("stability_verified", False)
        self.state = BridgeState.OPENING_PROTOCOL; self.health.write(self.state.value, **details)
    def frame(self, timestamp=None, **details):
        self.last_frame = timestamp or monotonic()
        if self.state == BridgeState.OPENING_PROTOCOL:
            self.state = BridgeState.VERIFYING_LIVE_INPUT
        if self.state == BridgeState.VERIFYING_LIVE_INPUT and self.verification.complete:
            self.state = BridgeState.CONNECTED
            self.failures = 0
            self.connected_at = self.last_frame
        details.setdefault("live_axes", sorted(self.verification.changed))
        details.setdefault("live_input_verified", self.verification.complete)
        stable_for = self.last_frame - self.connected_at if self.connected_at is not None else 0.0
        details.setdefault("stability_seconds", round(max(0.0, stable_for), 3))
        details.setdefault("stability_verified", self.state == BridgeState.CONNECTED and stable_for >= self.stability_seconds)
        self.health.write(self.state.value, last_valid_frame=self.last_frame, **details)
    def lost(self, reason=None):
        self.failures += 1; self.state = BridgeState.RECONNECT_BACKOFF
        self.connected_at = None
        delay = self.backoff_seconds[min(self.failures - 1, len(self.backoff_seconds) - 1)]
        details = {"retry_seconds": delay, "serial_open": False, "stability_verified": False}
        if reason: details["reason"] = reason
        self.health.write(self.state.value, **details)
        return delay
