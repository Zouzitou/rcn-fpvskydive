from rcn_fpv.discovery import PortCandidate, choose_candidate, classify_usb
from rcn_fpv.mapping import AxisConfig, map_axis, map_sticks
from rcn_fpv.protocol import encode, parse, parse_rcn1_sticks, crc8, crc16, build_read_sticks, parse_duml
from rcn_fpv.runtime import HealthStore, ProcessLock, SingletonError
from rcn_fpv.diagnostics import redact, report
from rcn_fpv.gamepad import NullBackend, self_test

def test_protocol_beats_debug_and_com_numbers_are_irrelevant():
    cs = [PortCandidate("COM12", "DJI For Debug", "2CA3", "1020", "MI_04"), PortCandidate("COM7", "DJI For Protocol", "2CA3", "1020", "MI_02")]
    assert choose_candidate(cs).device == "COM7"

def test_unknown_usb_is_not_accepted():
    assert choose_candidate([PortCandidate("COM1", "For Protocol", "1234", "5678", "MI_02")]) is None

def test_model_classification_does_not_overclaim():
    assert classify_usb("2CA3", "1020")["status"] == "supported"
    assert classify_usb("2CA3", "1021")["status"].startswith("requires Protocol")
    assert classify_usb("FFFF", "0001")["status"] == "unknown device"

def test_unconfirmed_dji_protocol_candidate_can_only_proceed_to_live_verification():
    candidate = PortCandidate("COM9", "DJI USB VCOM For Protocol", "2CA3", "1021", "MI_02")
    assert choose_candidate([candidate]) == candidate and candidate.proven_model is None

def test_bad_checksum_rejected():
    b = bytearray(encode(b"abc")); b[-1] ^= 1
    assert parse(b) == []

def test_rcn1_decoder_requires_valid_duml_frame():
    packet = bytearray(38); packet[0] = 0x55
    packet[1:3] = (38).to_bytes(2, "little"); packet[3] = crc8(packet[:3])
    for offset, value in ((13, 1684), (16, 364), (19, 1024), (22, 1024), (25, 1024)):
        packet[offset:offset + 2] = value.to_bytes(2, "little")
    packet[-2:] = crc16(packet[:-2]).to_bytes(2, "little")
    decoded = parse_rcn1_sticks(bytes(packet))
    assert decoded and decoded.right_h == 1684 and decoded.left_v == 1024
    packet[-1] ^= 1
    assert parse_rcn1_sticks(bytes(packet)) is None

def test_duml_read_sticks_command_is_valid():
    packet = build_read_sticks()
    assert len(packet) == 13 and parse_duml(packet) == packet[4:-2]

def test_mapping_dead_zone_and_inversion():
    assert map_axis(0.01, AxisConfig()) == 0
    assert map_axis(0.5, AxisConfig(invert=True)) < 0

def test_mode2_stick_mapping_is_explicit():
    frame = type("F", (), {"left_h": 1684, "left_v": 364, "right_h": 1024, "right_v": 1684})()
    axes = map_sticks(frame)
    assert axes["left_x"] > 0.9 and axes["left_y"] < -0.9
    assert abs(axes["right_x"]) < 0.01 and axes["right_y"] > 0.9

def test_singleton_and_health(tmp_path):
    lock = ProcessLock(tmp_path / "bridge.lock")
    assert lock.acquire()
    try:
        try: ProcessLock(tmp_path / "bridge.lock").acquire()
        except SingletonError: pass
        else: assert False, "second bridge must be rejected"
        HealthStore(tmp_path).write("waiting_for_controller")
        assert report(tmp_path)["health"]["state"] == "waiting_for_controller"
        assert report(tmp_path)["driver"] == "unknown"
    finally: lock.release()

def test_stale_singleton_lock_is_reclaimed(tmp_path, monkeypatch):
    path = tmp_path / "bridge.lock"
    path.write_text("pid=1234\nstarted=0\n", encoding="ascii")
    monkeypatch.setattr("rcn_fpv.runtime.os.kill", lambda *_: (_ for _ in ()).throw(ProcessLookupError()))
    lock = ProcessLock(path)
    assert lock.acquire()
    lock.release()

def test_inaccessible_singleton_lock_is_not_reclaimed(tmp_path, monkeypatch):
    path = tmp_path / "bridge.lock"
    path.write_text("pid=1234\nstarted=0\n", encoding="ascii")
    monkeypatch.setattr("rcn_fpv.runtime.os.kill", lambda *_: (_ for _ in ()).throw(PermissionError()))
    try:
        ProcessLock(path).acquire()
    except SingletonError:
        pass
    else:
        assert False, "an inaccessible lock must fail closed"

def test_gamepad_self_test_releases_backend():
    backend = NullBackend()
    result = self_test(backend)
    assert result.passed
    assert backend.events[-1] == ("release",)

def test_diagnostic_redaction_preserves_json_structure():
    value = redact({"port": "COM12", "ready": True, "none": None, "items": [1, "C:\\Users\\alice\\x"]})
    assert value["port"] == "COM12" and value["ready"] is True and value["none"] is None
    assert value["items"] == [1, "C:\\Users\\<user>\\x"]

def test_health_retains_gamepad_evidence_across_state_changes(tmp_path):
    store = HealthStore(tmp_path)
    store.write("gamepad_ready", virtual_gamepad_test="passed", protocol_port="COM12", usb_instance_id="MI_02")
    store.write("waiting_for_controller")
    assert report(tmp_path)["health"]["virtual_gamepad_test"] == "passed"
    assert report(tmp_path)["health"]["protocol_port"] == "COM12"
