from time import monotonic

from .gamepad import self_test
from .lifecycle import BridgeState, Lifecycle
from .runtime import ProcessLock, SingletonError
from .logging import JsonlLogger
from .protocol import parse_rcn1_sticks, build_enable_simulator, build_read_sticks
from .mapping import map_sticks

class Bridge:
    def __init__(self, root, discovery, transport_factory, output, health, axis_configs=None):
        self.root = root; self.discovery = discovery; self.transport_factory = transport_factory
        self.output = output; self.health = health; self.lifecycle = Lifecycle(health)
        self.logger = JsonlLogger(root)
        self.lock = ProcessLock(root / "state" / "bridge.lock"); self.transport = None
        self.last_frame_at = None
        self.last_frame_log_at = None
        self.last_wait_logged_at = None
        self.next_connect_at = 0.0
        self.axis_configs = axis_configs
        self.previous_axes = {k: 0.0 for k in ("left_x", "left_y", "right_x", "right_y")}
        self.packet_count = 0
        self.valid_frame_count = 0
    def start(self):
        self.lock.acquire()
        self.logger.event("bridge_start", pid=__import__("os").getpid())
        self.output.neutral(); self.output.release_buttons()
        self.lifecycle.waiting()
    def connect_if_available(self):
        candidate = self.discovery()
        if candidate is None:
            self.lifecycle.waiting()
            now = monotonic()
            if self.last_wait_logged_at is None or now - self.last_wait_logged_at >= 30:
                self.logger.event("waiting_for_controller")
                self.last_wait_logged_at = now
            return False
        classification = candidate.proven_model or "RC-N family unconfirmed"
        self.lifecycle.candidate_found(protocol_port=candidate.device, usb_instance_id=candidate.instance_id,
                                       controller_model=classification)
        self.logger.event("protocol_candidate", device=candidate.device, instance_id=candidate.instance_id,
                          controller_model=classification)
        self.transport = self.transport_factory(candidate)
        result = self.transport.open()
        self.health.write(self.lifecycle.state.value, protocol_port=candidate.device,
                          usb_instance_id=candidate.instance_id, controller_model=classification, serial_open=True,
                          packet_count=self.packet_count, valid_frame_count=self.valid_frame_count)
        if hasattr(self.transport, "write"):
            self.transport.write(build_enable_simulator())
            self.transport.write(build_read_sticks())
        self.logger.event("protocol_open", message=getattr(result, "message", "opened")); return True
    def poll_once(self):
        if self.transport is None:
            if monotonic() < self.next_connect_at:
                return False
            return self.connect_if_available()
        if hasattr(self.transport, "write"):
            self.transport.write(build_read_sticks())
        frames = self.transport.read_frames()
        self.packet_count += len(frames)
        valid = 0
        for packet in frames:
            decoded = parse_rcn1_sticks(packet)
            if decoded is None: continue
            axes = map_sticks(decoded, self.axis_configs)
            for name, value in axes.items(): self.lifecycle.verification.observe(name, self.previous_axes[name], value)
            self.previous_axes = axes; valid += 1; self.valid_frame_count += 1
            if self.lifecycle.state == BridgeState.CONNECTED and hasattr(self.output, "set_axes"):
                self.output.set_axes(axes)
        if valid:
            self.last_frame_at = monotonic()
            self.lifecycle.frame(self.last_frame_at, serial_open=True, packet_count=self.packet_count,
                                 valid_frame_count=self.valid_frame_count)
            if self.last_frame_log_at is None or self.last_frame_at - self.last_frame_log_at >= 5:
                self.logger.event("valid_frames", count=valid)
                self.last_frame_log_at = self.last_frame_at
        elif frames:
            self.health.write(self.lifecycle.state.value, serial_open=True, packet_count=self.packet_count,
                              valid_frame_count=self.valid_frame_count)
        return bool(valid)
    def disconnect(self, reason="transport lost"):
        if self.transport:
            self.transport.close(); self.transport = None
        delay = self.lifecycle.lost(reason)
        self.next_connect_at = monotonic() + delay
        self.previous_axes = {name: 0.0 for name in self.previous_axes}
        self.logger.event("transport_lost", retry_seconds=delay, reason=reason)
        self.output.neutral(); self.output.release_buttons()
    def stop(self):
        try:
            if self.transport: self.transport.close()
            self.output.neutral(); self.output.release_buttons()
        finally:
            self.transport = None; self.lock.release()
            self.logger.event("bridge_stop")
