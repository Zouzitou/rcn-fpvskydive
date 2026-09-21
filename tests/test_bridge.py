from rcn_fpv.bridge import Bridge
from rcn_fpv.runtime import HealthStore
from rcn_fpv.discovery import PortCandidate
from rcn_fpv.protocol import crc8, crc16

class Output:
    def __init__(self): self.events=[]
    def neutral(self): self.events.append("neutral")
    def release_buttons(self): self.events.append("release")

class Transport:
    def __init__(self, candidate): self.opened=False; self.closed=False; self.writes=[]
    def open(self): self.opened=True
    def write(self, data): self.writes.append(data); return len(data)
    def read_frames(self): return []
    def close(self): self.closed=True

def packet(values):
    packet = bytearray(38); packet[0] = 0x55; packet[1:3] = (38).to_bytes(2, "little"); packet[3] = crc8(packet[:3])
    for offset, value in zip((13, 16, 19, 22), values): packet[offset:offset + 2] = value.to_bytes(2, "little")
    packet[25:27] = (1024).to_bytes(2, "little"); packet[-2:] = crc16(packet[:-2]).to_bytes(2, "little")
    return bytes(packet)

def test_bridge_starts_neutral_and_stops_cleanly(tmp_path):
    output=Output(); bridge=Bridge(tmp_path, lambda: None, Transport, output, HealthStore(tmp_path))
    bridge.start(); bridge.poll_once(); bridge.stop()
    assert output.events == ["neutral", "release", "neutral", "release"]

def test_bridge_rate_limits_waiting_log(tmp_path):
    bridge = Bridge(tmp_path, lambda: None, Transport, Output(), HealthStore(tmp_path))
    bridge.start(); bridge.poll_once(); bridge.poll_once(); bridge.stop()
    lines = (tmp_path / "logs" / "bridge.jsonl").read_text(encoding="utf-8").splitlines()
    assert sum('"event":"waiting_for_controller"' in line for line in lines) == 1

def test_bridge_waits_for_reconnect_backoff(tmp_path):
    calls = []
    bridge = Bridge(tmp_path, lambda: calls.append(1), Transport, Output(), HealthStore(tmp_path))
    bridge.start(); bridge.next_connect_at = float("inf")
    assert bridge.poll_once() is False and not calls
    bridge.stop()

def test_bridge_opens_only_discovered_candidate(tmp_path):
    port=PortCandidate("COM9", "For Protocol", "2CA3", "1020", "MI_02")
    bridge=Bridge(tmp_path, lambda: port, Transport, Output(), HealthStore(tmp_path))
    bridge.start(); assert bridge.connect_if_available(); assert bridge.transport.opened
    bridge.poll_once(); assert len(bridge.transport.writes) == 3; bridge.stop()
    health = HealthStore(tmp_path).path.read_text(encoding="utf-8")
    assert '"protocol_port": "COM9"' in health and '"usb_instance_id": "MI_02"' in health
    assert '"serial_open": true' in health and '"packet_count": 0' in health

def test_bridge_emits_axes_only_after_live_verification(tmp_path):
    class LiveTransport(Transport):
        def __init__(self, candidate): super().__init__(candidate); self.frames = [packet((1684, 364, 1684, 364))] * 2
        def read_frames(self): return [self.frames.pop(0)] if self.frames else []
    output=Output(); bridge=Bridge(tmp_path, lambda: PortCandidate("COM9", "For Protocol", "2CA3", "1020", "MI_02"), LiveTransport, output, HealthStore(tmp_path))
    bridge.start(); bridge.connect_if_available(); bridge.poll_once(); assert "neutral" in output.events
    bridge.poll_once(); bridge.stop(); assert output.events.count("neutral") >= 2
    health = HealthStore(tmp_path).path.read_text(encoding="utf-8")
    assert '"packet_count": 2' in health and '"valid_frame_count": 2' in health
