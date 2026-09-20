from dataclasses import dataclass
from typing import Optional

@dataclass(frozen=True)
class Frame:
    payload: bytes

@dataclass(frozen=True)
class StickFrame:
    right_h: int
    right_v: int
    left_v: int
    left_h: int
    camera: int
    buttons: int
    format: str = "rc-n1-38"

def crc8(data: bytes, seed=0x77):
    crc = seed
    for byte in data:
        crc ^= byte
        for _ in range(8): crc = (crc >> 1) ^ 0x8C if crc & 1 else crc >> 1
    return crc

def crc16(data: bytes, seed=0x3692):
    crc = seed
    for byte in data:
        crc ^= byte
        for _ in range(8): crc = (crc >> 1) ^ 0x8408 if crc & 1 else crc >> 1
    return crc

def parse_duml(data: bytes) -> Optional[bytes]:
    """Validate one complete DUML packet and return its payload body."""
    if len(data) < 13 or data[0] != 0x55: return None
    length = int.from_bytes(data[1:3], "little") & 0x03FF
    if length != len(data) or crc8(data[:3]) != data[3]: return None
    if crc16(data[:-2]).to_bytes(2, "little") != data[-2:]: return None
    return data[4:-2]

def parse_rcn1_sticks(packet: bytes) -> Optional[StickFrame]:
    """Decode only the validated 38-byte RC-N1 serial response layout."""
    if len(packet) != 38: return None
    body = parse_duml(packet)
    if body is None or len(body) < 28: return None
    # Offsets are within the complete DUML packet, as established by protocol research.
    def value(offset): return int.from_bytes(packet[offset:offset + 2], "little")
    return StickFrame(value(13), value(16), value(19), value(22), value(25), packet[12])

def parse_duml_stream(buffer: bytearray):
    """Extract validated DUML packets from a serial byte stream."""
    packets = []
    while True:
        try: start = buffer.index(0x55)
        except ValueError: buffer.clear(); break
        if start: del buffer[:start]
        if len(buffer) < 4: break
        length = int.from_bytes(buffer[1:3], "little") & 0x03FF
        if length < 13 or length > 1024:
            del buffer[0]; continue
        if len(buffer) < length: break
        packet = bytes(buffer[:length])
        del buffer[:length]
        if parse_duml(packet) is not None: packets.append(packet)
    return packets

def checksum(data: bytes) -> int:
    return sum(data) & 0xFF

def encode(payload: bytes) -> bytes:
    body = len(payload).to_bytes(2, "little") + payload
    return b"\x55" + body + bytes([checksum(body)])

def parse(buffer: bytearray):
    frames = []
    while True:
        if len(buffer) < 4:
            break
        try:
            start = buffer.index(0x55)
        except ValueError:
            buffer.clear(); break
        if start:
            del buffer[:start]
        length = int.from_bytes(buffer[1:3], "little")
        total = 4 + length
        if length < 1 or len(buffer) < total:
            break
        body = bytes(buffer[1:4 + length])
        if checksum(body[:-1]) == body[-1]:
            frames.append(Frame(body[2:-1]))
        del buffer[:total]
    return frames
