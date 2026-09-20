from dataclasses import dataclass

class GamepadUnavailable(RuntimeError): pass

class NullBackend:
    """Test backend; records calls and never touches a host virtual device."""
    def __init__(self): self.events = []
    def create(self): self.events.append(("create",))
    def axis(self, name, value): self.events.append(("axis", name, value))
    def update(self): self.events.append(("update",))
    def release(self): self.events.append(("release",))

class XboxOutput:
    def __init__(self, backend): self.backend = backend; self.axes = {k: 0.0 for k in ("left_x", "left_y", "right_x", "right_y")}
    def neutral(self):
        for axis in self.axes: self.axes[axis] = 0.0
        for axis, value in self.axes.items(): self.backend.axis(axis, value)
        self.backend.update()
    def release_buttons(self): self.backend.release()
    def set_axes(self, values):
        self.axes.update(values)
        for axis, value in self.axes.items(): self.backend.axis(axis, value)
        self.backend.update()

class VigemBackend:
    def __init__(self):
        try:
            import vgamepad as vg
        except ImportError as exc:
            raise GamepadUnavailable("vgamepad is not installed") from exc
        self.vg = vg; self.pad = None
    def create(self): self.pad = self.vg.VX360Gamepad()
    def axis(self, name, value):
        if self.pad is None: raise GamepadUnavailable("gamepad not created")
        value = max(-1.0, min(1.0, float(value)))
        raw = int(value * 32767)
        if name == "left_x": self.pad.left_joystick(x_value=raw, y_value=0)
        elif name == "left_y": self.pad.left_joystick(x_value=0, y_value=raw)
        elif name == "right_x": self.pad.right_joystick(x_value=raw, y_value=0)
        elif name == "right_y": self.pad.right_joystick(x_value=0, y_value=raw)
        else: raise ValueError(f"unknown axis: {name}")
    def update(self):
        if self.pad: self.pad.update()
    def release(self):
        if self.pad: self.pad.reset(); self.pad.update(); self.pad = None

@dataclass
class SelfTestResult:
    passed: bool
    message: str

def self_test(backend=None):
    backend = backend or VigemBackend()
    try:
        backend.create()
        backend.axis("left_x", 0.15)
        backend.update()
        return SelfTestResult(True, "virtual Xbox controller created, updated, and released")
    except Exception as exc:
        return SelfTestResult(False, f"virtual gamepad self-test failed: {exc}")
    finally:
        try: backend.release()
        except Exception: pass
