from time import monotonic

from .gamepad import self_test
from .lifecycle import BridgeState, Lifecycle
from .runtime import ProcessLock, SingletonError
from .logging import JsonlLogger
from .protocol import parse_rcn1_sticks
from .mapping import map_sticks

class Bridge:
    def __init__(self, root, discovery, transport_factory, output, health):
        self.root = root; self.discovery = discovery; self.transport_factory = transport_factory
        self.output = output; self.health = health; self.lifecycle = Lifecycle(health)
        self.logger = JsonlLogger(root)
        self.lock = ProcessLock(root / "state" / "bridge.lock"); self.transport = None
        self.last_frame_at = None
        self.previous_axes = {k: 0.0 for k in ("left_x", "left_y", "right_x", "right_y")}
    def start(self):
        self.lock.acquire()
        self.logger.event("bridge_start", pid=__import__("os").getpid())
        self.output.neutral(); self.output.release_buttons()
        self.lifecycle.waiting()
    def connect_if_available(self):
        candidate = self.discovery()
        if candidate is None: self.lifecycle.waiting(); self.logger.event("waiting_for_controller"); return False
        self.lifecycle.candidate_found()
        self.logger.event("protocol_candidate", device=candidate.device, instance_id=candidate.instance_id)
        self.transport = self.transport_factory(candidate)
        result = self.transport.open()
        self.logger.event("protocol_open", message=getattr(result, "message", "opened")); return True
    def poll_once(self):
        if self.transport is None:
            return self.connect_if_available()
        frames = self.transport.read_frames()
        valid = 0
        for packet in frames:
            decoded = parse_rcn1_sticks(packet)
            if decoded is None: continue
            axes = map_sticks(decoded)
            for name, value in axes.items(): self.lifecycle.verification.observe(name, self.previous_axes[name], value)
            self.previous_axes = axes; valid += 1
            if self.lifecycle.state == BridgeState.CONNECTED and hasattr(self.output, "set_axes"):
                self.output.set_axes(axes)
        if valid:
            self.last_frame_at = monotonic(); self.lifecycle.frame(self.last_frame_at)
            self.logger.event("valid_frames", count=valid)
        return bool(valid)
    def disconnect(self):
        if self.transport:
            self.transport.close(); self.transport = None
        self.logger.event("transport_lost")
        self.output.neutral(); self.output.release_buttons(); self.lifecycle.lost()
    def stop(self):
        try:
            if self.transport: self.transport.close()
            self.output.neutral(); self.output.release_buttons()
        finally:
            self.transport = None; self.lock.release()
            self.logger.event("bridge_stop")
