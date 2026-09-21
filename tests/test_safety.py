from rcn_fpv import driver
from rcn_fpv.driver import DriverEvidence, DriverInstallError, driver_install_command, managed_inf, pnputil_command, validate_driver, parse_driver_output
from rcn_fpv.startup import choose_startup_method
from rcn_fpv.lifecycle import BridgeState, Lifecycle
from rcn_fpv.runtime import HealthStore
from rcn_fpv.discovery import PortCandidate
from rcn_fpv.protocol import encode, crc8, crc16
from rcn_fpv.transport import SerialTransport, TransportError
from rcn_fpv.watchdog import run as watchdog_run

def test_driver_validation_fails_closed():
    ok, reasons = validate_driver(DriverEvidence("DJI", "1", False, ("USB\\VID_2CA3&PID_1020",), True))
    assert not ok and "signature" in reasons[0]

def test_driver_validation_requires_dji_provider():
    ok, reasons = validate_driver(DriverEvidence("Other", "1", True, ("USB\\VID_2CA3&PID_1020",), True))
    assert not ok and "provider" in reasons[0]

def test_driver_command_is_explicit():
    assert pnputil_command("dji_vcom_driver11.inf") == ["pnputil.exe", "/add-driver", "dji_vcom_driver11.inf", "/install"]

def test_driver_install_command_requests_elevation():
    assert "-Verb RunAs" in driver_install_command("C:/drivers/dji.inf")[-1]

def test_managed_inf_rejects_outside_payload(tmp_path):
    inf = tmp_path / "other.inf"; inf.write_text("", encoding="utf-8")
    try: managed_inf(tmp_path, inf)
    except DriverInstallError: pass
    else: assert False, "driver payload must stay in its managed folder"

def test_driver_output_parser_is_conservative():
    evidence = parse_driver_output("Provider Name: DJI\nDriver Version: 1.2\nClass Name: Ports\nDigitally Signed: Yes\nUSB\\VID_2CA3&PID_1020")
    assert evidence.provider == "DJI" and evidence.ports_class and evidence.signed
    assert validate_driver(evidence)[0]

def test_driver_output_parser_rejects_explicit_unsigned_result():
    evidence = parse_driver_output("Class Name: Ports\nDigitally Signed: No\nUSB\\VID_2CA3&PID_1020")
    assert not evidence.signed and not validate_driver(evidence)[0]

def test_cim_driver_discovery_uses_signed_ports_evidence(monkeypatch):
    response = type("Result", (), {"returncode": 0, "stdout": '{"Manufacturer":"DJI","DriverVersion":"1","IsSigned":true,"DeviceClass":"Ports","DeviceID":"USB\\\\VID_2CA3&PID_1020"}'})()
    monkeypatch.setattr(driver.subprocess, "run", lambda *_, **__: response)
    evidence = driver.discover_driver_evidence()
    assert evidence and validate_driver(evidence)[0]

def test_startup_fallback_order():
    assert choose_startup_method(True, True).method == "scheduled-task"
    assert choose_startup_method(False, True).method == "startup-folder"
    assert choose_startup_method(False, False).method == "none"

def test_lifecycle_requires_all_live_axes(tmp_path):
    life = Lifecycle(HealthStore(tmp_path))
    life.candidate_found(); assert life.state == BridgeState.OPENING_PROTOCOL
    life.frame(1.0); assert life.state == BridgeState.VERIFYING_LIVE_INPUT
    for axis in life.verification.required_axes: life.verification.observe(axis, 0.0, 0.2)
    life.frame(2.0); assert life.state == BridgeState.CONNECTED
    health = HealthStore(tmp_path).path.read_text(encoding="utf-8")
    assert '"live_input_verified": true' in health and '"left_x"' in health
    assert life.lost() == 1

def test_lifecycle_requires_a_stability_interval_after_live_verification(tmp_path):
    store = HealthStore(tmp_path); life = Lifecycle(store, stability_seconds=10)
    life.candidate_found(); life.frame(1.0)
    for axis in life.verification.required_axes: life.verification.observe(axis, 0.0, 0.2)
    life.frame(2.0)
    assert '"stability_verified": false' in store.path.read_text(encoding="utf-8")
    life.frame(12.0)
    assert '"stability_verified": true' in store.path.read_text(encoding="utf-8")

def test_lifecycle_requires_fresh_live_input_after_reconnect(tmp_path):
    life = Lifecycle(HealthStore(tmp_path))
    life.candidate_found(); life.frame(1.0)
    for axis in life.verification.required_axes: life.verification.observe(axis, 0.0, 0.2)
    life.frame(2.0); assert life.state == BridgeState.CONNECTED
    life.lost(); life.candidate_found(); life.frame(3.0)
    assert life.state == BridgeState.VERIFYING_LIVE_INPUT

def test_lifecycle_records_reconnect_reason(tmp_path):
    store = HealthStore(tmp_path); life = Lifecycle(store)
    life.lost("Protocol port is busy")
    assert store.path.read_text(encoding="utf-8").find("Protocol port is busy") >= 0
    assert '"serial_open": false' in store.path.read_text(encoding="utf-8")

def test_transport_reads_incremental_frames():
    class FakeSerial:
        def __init__(self, *args, **kwargs): self.closed = False; self.kwargs = kwargs
        def read(self, _):
            packet = bytearray(13); packet[0] = 0x55; packet[1:3] = (13).to_bytes(2, "little")
            packet[3] = crc8(packet[:3]); packet[-2:] = crc16(packet[:-2]).to_bytes(2, "little")
            return bytes(packet)
        def write(self, data): return len(data)
        def close(self): self.closed = True
    port = PortCandidate("COM8", "DJI For Protocol", "2CA3", "1020", "MI_02")
    transport = SerialTransport(port, timeout=0.01, serial_factory=FakeSerial)
    assert transport.open().opened
    assert transport.serial.kwargs["timeout"] == 0.01
    assert transport.read_frames()[0][0] == 0x55
    transport.close()

def test_transport_rejects_debug_port():
    port = PortCandidate("COM8", "DJI For Debug", "2CA3", "1020", "MI_04")
    try: SerialTransport(port)
    except TransportError: pass
    else: assert False, "debug interface must never be opened"
