from time import monotonic

from .gamepad import self_test
from .lifecycle import BridgeState, Lifecycle
from .runtime import ProcessLock, SingletonError

class Bridge:
    def __init__(self, root, discovery, transport_factory, output, health):
        self.root = root; self.discovery = discovery; self.transport_factory = transport_factory
        self.output = output; self.health = health; self.lifecycle = Lifecycle(health)
        self.lock = ProcessLock(root / "state" / "bridge.lock"); self.transport = None
        self.last_frame_at = None
    def start(self):
        self.lock.acquire()
        self.output.neutral(); self.output.release_buttons()
        self.lifecycle.waiting()
    def connect_if_available(self):
        candidate = self.discovery()
        if candidate is None: self.lifecycle.waiting(); return False
        self.lifecycle.candidate_found()
        self.transport = self.transport_factory(candidate)
        self.transport.open(); return True
    def poll_once(self):
        if self.transport is None:
            return self.connect_if_available()
        frames = self.transport.read_frames()
        if frames:
            self.last_frame_at = monotonic(); self.lifecycle.frame(self.last_frame_at)
        return bool(frames)
    def disconnect(self):
        if self.transport:
            self.transport.close(); self.transport = None
        self.output.neutral(); self.output.release_buttons(); self.lifecycle.lost()
    def stop(self):
        try:
            if self.transport: self.transport.close()
            self.output.neutral(); self.output.release_buttons()
        finally:
            self.transport = None; self.lock.release()
