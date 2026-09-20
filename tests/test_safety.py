from rcn_fpv.driver import DriverEvidence, pnputil_command, validate_driver
from rcn_fpv.startup import choose_startup_method
from rcn_fpv.lifecycle import BridgeState, Lifecycle
from rcn_fpv.runtime import HealthStore

def test_driver_validation_fails_closed():
    ok, reasons = validate_driver(DriverEvidence("DJI", "1", False, ("USB\\VID_2CA3&PID_1020",), True))
    assert not ok and "signature" in reasons[0]

def test_driver_command_is_explicit():
    assert pnputil_command("dji_vcom_driver11.inf") == ["pnputil.exe", "/add-driver", "dji_vcom_driver11.inf", "/install"]

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
    assert life.lost() == 1
