from dataclasses import dataclass

@dataclass(frozen=True)
class Frame:
    payload: bytes

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
