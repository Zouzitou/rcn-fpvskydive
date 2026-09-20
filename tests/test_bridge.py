from rcn_fpv.bridge import Bridge
from rcn_fpv.runtime import HealthStore
from rcn_fpv.discovery import PortCandidate

class Output:
    def __init__(self): self.events=[]
    def neutral(self): self.events.append("neutral")
    def release_buttons(self): self.events.append("release")

class Transport:
    def __init__(self, candidate): self.opened=False; self.closed=False
    def open(self): self.opened=True
    def read_frames(self): return []
    def close(self): self.closed=True

def test_bridge_starts_neutral_and_stops_cleanly(tmp_path):
    output=Output(); bridge=Bridge(tmp_path, lambda: None, Transport, output, HealthStore(tmp_path))
    bridge.start(); bridge.poll_once(); bridge.stop()
    assert output.events == ["neutral", "release", "neutral", "release"]

def test_bridge_opens_only_discovered_candidate(tmp_path):
    port=PortCandidate("COM9", "For Protocol", "2CA3", "1020", "MI_02")
    bridge=Bridge(tmp_path, lambda: port, Transport, Output(), HealthStore(tmp_path))
    bridge.start(); assert bridge.connect_if_available(); assert bridge.transport.opened; bridge.stop()
