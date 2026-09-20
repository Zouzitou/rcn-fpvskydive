from rcn_fpv.driver import DriverEvidence, pnputil_command, validate_driver
from rcn_fpv.startup import choose_startup_method

def test_driver_validation_fails_closed():
    ok, reasons = validate_driver(DriverEvidence("DJI", "1", False, ("USB\\VID_2CA3&PID_1020",), True))
    assert not ok and "signature" in reasons[0]

def test_driver_command_is_explicit():
    assert pnputil_command("dji_vcom_driver11.inf") == ["pnputil.exe", "/add-driver", "dji_vcom_driver11.inf", "/install"]

def test_startup_fallback_order():
    assert choose_startup_method(True, True).method == "scheduled-task"
    assert choose_startup_method(False, True).method == "startup-folder"
    assert choose_startup_method(False, False).method == "none"
