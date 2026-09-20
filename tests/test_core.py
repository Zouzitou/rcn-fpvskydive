from rcn_fpv.discovery import PortCandidate, choose_candidate
from rcn_fpv.mapping import AxisConfig, map_axis
from rcn_fpv.protocol import encode, parse
from rcn_fpv.runtime import HealthStore, ProcessLock, SingletonError
from rcn_fpv.diagnostics import report
from rcn_fpv.gamepad import NullBackend, self_test

def test_protocol_beats_debug_and_com_numbers_are_irrelevant():
    cs = [PortCandidate("COM12", "DJI For Debug", "2CA3", "1020", "MI_04"), PortCandidate("COM7", "DJI For Protocol", "2CA3", "1020", "MI_02")]
    assert choose_candidate(cs).device == "COM7"

def test_unknown_usb_is_not_accepted():
    assert choose_candidate([PortCandidate("COM1", "For Protocol", "1234", "5678", "MI_02")]) is None

def test_bad_checksum_rejected():
    b = bytearray(encode(b"abc")); b[-1] ^= 1
    assert parse(b) == []

def test_mapping_dead_zone_and_inversion():
    assert map_axis(0.01, AxisConfig()) == 0
    assert map_axis(0.5, AxisConfig(invert=True)) < 0

def test_singleton_and_health(tmp_path):
    lock = ProcessLock(tmp_path / "bridge.lock")
    assert lock.acquire()
    try:
        try: ProcessLock(tmp_path / "bridge.lock").acquire()
        except SingletonError: pass
        else: assert False, "second bridge must be rejected"
        HealthStore(tmp_path).write("waiting_for_controller")
        assert report(tmp_path)["health"]["state"] == "waiting_for_controller"
    finally: lock.release()

def test_gamepad_self_test_releases_backend():
    backend = NullBackend()
    result = self_test(backend)
    assert result.passed
    assert backend.events[-1] == ("release",)
