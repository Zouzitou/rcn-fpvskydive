# RC-N1 hardware evidence

Captured on 2026-09-21 on Windows with the controller powered through its data port.

## Windows interface evidence

- USB identity: `VID_2CA3`, `PID_1020`
- Protocol interface: `MI_02`, `DEVICE USB VCOM For Protocol (COM12)`
- Debug interface: `MI_04`, `DEVICE USB VCOM For Debug (COM11)`
- The bridge must use COM12/`MI_02`; COM11 is explicitly not a setup success.

## Native serial probe

A PowerShell/.NET `SerialPort` probe, rather than Python, opened COM12 at 115200 baud. It sent the existing simulator-enable DuML command and repeated stick-poll command. The controller returned 90 complete 38-byte stick responses during the seven-second capture.

| Raw field | Observed minimum | Observed maximum | Changed |
|---|---:|---:|---|
| Right horizontal | 364 | 1684 | Yes |
| Right vertical | 364 | 1684 | Yes |
| Left vertical | 364 | 1406 | Yes |
| Left horizontal | 364 | 1684 | Yes |

This validates the selected RC-N1 Protocol interface, the simulator-enable/poll request sequence, the 38-byte response layout, and the four stick offsets used by the bridge.

## Virtual-controller host prerequisite

Windows reports `Nefarius Virtual Gamepad Emulation Bus` present and `OK`. The native Rust bridge's 2026-09-21 self-test created a ViGEm Xbox 360 target, applied a temporary left-axis value, explicitly sent neutral output, and exited successfully. Its two-second `bridge-smoke` test then mapped 97 validated COM12 stick frames through that target and again sent neutral output before exit.

This proves the native protocol-to-virtual-controller path on this host. Automatic startup, a released installer, FPV SkyDive calibration, reconnect/sleep behavior, and clean-machine validation remain separate release gates.
