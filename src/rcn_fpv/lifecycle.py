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
    def __init__(self, health, backoff_seconds=(1, 2, 5, 10, 30)):
        self.health = health; self.state = BridgeState.WAITING_FOR_CONTROLLER
        self.backoff_seconds = tuple(backoff_seconds); self.failures = 0; self.verification = LiveVerification()
        self.last_frame = None
    def waiting(self):
        self.state = BridgeState.WAITING_FOR_CONTROLLER; self.health.write(self.state.value)
    def candidate_found(self):
        self.verification = LiveVerification()
        self.state = BridgeState.OPENING_PROTOCOL; self.health.write(self.state.value)
    def frame(self, timestamp=None):
        self.last_frame = timestamp or monotonic()
        if self.state == BridgeState.OPENING_PROTOCOL:
            self.state = BridgeState.VERIFYING_LIVE_INPUT
        if self.state == BridgeState.VERIFYING_LIVE_INPUT and self.verification.complete:
            self.state = BridgeState.CONNECTED
            self.failures = 0
        self.health.write(self.state.value, last_valid_frame=self.last_frame)
    def lost(self):
        self.failures += 1; self.state = BridgeState.RECONNECT_BACKOFF
        delay = self.backoff_seconds[min(self.failures - 1, len(self.backoff_seconds) - 1)]
        self.health.write(self.state.value, retry_seconds=delay)
        return delay
