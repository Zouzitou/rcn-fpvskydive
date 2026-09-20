from dataclasses import dataclass
from typing import Callable, Optional

from .discovery import PortCandidate
from .protocol import parse_duml_stream

class TransportError(RuntimeError): pass

@dataclass
class TransportResult:
    opened: bool
    message: str

class SerialTransport:
    def __init__(self, candidate: PortCandidate, baudrate=115200, serial_factory=None):
        if not candidate.is_protocol or candidate.is_debug:
            raise TransportError("refusing to open non-Protocol or Debug interface")
        self.candidate = candidate; self.baudrate = baudrate
        self.serial_factory = serial_factory; self.serial = None; self.buffer = bytearray()
    def open(self):
        try:
            factory = self.serial_factory
            if factory is None:
                from serial import Serial
                factory = Serial
            self.serial = factory(self.candidate.device, self.baudrate, timeout=0.2)
            return TransportResult(True, f"opened Protocol port {self.candidate.device}")
        except Exception as exc:
            raise TransportError(f"unable to open Protocol port {self.candidate.device}: {exc}") from exc
    def read_frames(self, on_frame: Optional[Callable] = None):
        if self.serial is None: raise TransportError("transport is not open")
        chunk = self.serial.read(4096)
        if chunk: self.buffer.extend(chunk)
        frames = parse_duml_stream(self.buffer)
        if on_frame:
            for frame in frames: on_frame(frame)
        return frames
    def write(self, data: bytes):
        if self.serial is None: raise TransportError("transport is not open")
        return self.serial.write(data)
    def close(self):
        if self.serial is not None:
            try: self.serial.close()
            finally: self.serial = None
