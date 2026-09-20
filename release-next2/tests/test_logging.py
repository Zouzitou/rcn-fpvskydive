from rcn_fpv.logging import JsonlLogger, tail
from rcn_fpv.gamepad import NullBackend, XboxOutput

def test_jsonl_logging_and_tail(tmp_path):
    logger = JsonlLogger(tmp_path); logger.event("startup", port="COM7")
    assert '"event":"startup"' in tail(logger.path)[0]

def test_xbox_output_neutral_and_axes():
    backend = NullBackend(); output = XboxOutput(backend)
    output.set_axes({"left_x": 0.5}); output.neutral(); output.release_buttons()
    assert backend.events[-1] == ("release",)
