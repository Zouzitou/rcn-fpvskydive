from dataclasses import dataclass, field
from enum import Enum

class InstallState(str, Enum):
    DISCOVER = "discover"
    FETCH_VERIFIED = "fetch_verified"
    PREPARE_ENV = "prepare_env"
    DRIVER_GATE = "driver_gate"
    GAMEPAD_SELF_TEST = "gamepad_self_test"
    STARTUP_TEST = "startup_test"
    HARDWARE_GUIDE = "hardware_guide"
    STABILITY_CHECK = "stability_check"
    READY = "ready"
    FAILED = "failed"

@dataclass
class InstallGates:
    artifact_verified: bool = False
    environment_ready: bool = False
    driver_valid: bool = False
    gamepad_ok: bool = False
    startup_ok: bool = False
    supported_protocol: bool = False
    live_input_verified: bool = False
    stable: bool = False
    failures: list[str] = field(default_factory=list)

class InstallerStateMachine:
    def __init__(self): self.state = InstallState.DISCOVER; self.gates = InstallGates()
    def fail(self, reason): self.gates.failures.append(reason); self.state = InstallState.FAILED
    def advance(self):
        g = self.gates
        if self.state == InstallState.DISCOVER: self.state = InstallState.FETCH_VERIFIED
        elif self.state == InstallState.FETCH_VERIFIED:
            self.state = InstallState.PREPARE_ENV if g.artifact_verified else self._fail("artifact hash/signature not verified")
        elif self.state == InstallState.PREPARE_ENV:
            self.state = InstallState.DRIVER_GATE if g.environment_ready else self._fail("managed environment is not ready")
        elif self.state == InstallState.DRIVER_GATE:
            self.state = InstallState.GAMEPAD_SELF_TEST if g.driver_valid else self._fail("driver evidence is invalid")
        elif self.state == InstallState.GAMEPAD_SELF_TEST:
            self.state = InstallState.STARTUP_TEST if g.gamepad_ok else self._fail("virtual gamepad self-test failed")
        elif self.state == InstallState.STARTUP_TEST:
            self.state = InstallState.HARDWARE_GUIDE if g.startup_ok else self._fail("startup test failed")
        elif self.state == InstallState.HARDWARE_GUIDE:
            self.state = InstallState.STABILITY_CHECK if g.supported_protocol and g.live_input_verified else self._fail("supported Protocol and live input are required")
        elif self.state == InstallState.STABILITY_CHECK:
            self.state = InstallState.READY if g.stable else self._fail("stability interval failed")
        return self.state
    def _fail(self, reason): self.fail(reason); return InstallState.FAILED
