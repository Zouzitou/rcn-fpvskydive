# Native Rust bridge

`rcn-bridge` is the production native runtime. It uses the RC-N1 hardware-verified DuML enable/poll sequence and creates a ViGEm Xbox 360 target without Python.

```powershell
cargo test --manifest-path rust-bridge/Cargo.toml
cargo run --manifest-path rust-bridge/Cargo.toml -- status
cargo run --manifest-path rust-bridge/Cargo.toml -- diagnose
cargo run --manifest-path rust-bridge/Cargo.toml -- start
cargo run --manifest-path rust-bridge/Cargo.toml -- stop
cargo run --manifest-path rust-bridge/Cargo.toml -- open-fpv
cargo run --manifest-path rust-bridge/Cargo.toml -- verify-input
cargo run --manifest-path rust-bridge/Cargo.toml -- self-test
cargo run --manifest-path rust-bridge/Cargo.toml -- probe --port COM12
cargo run --manifest-path rust-bridge/Cargo.toml -- bridge-smoke --port COM12
cargo run --manifest-path rust-bridge/Cargo.toml -- bridge --port COM12
```

`status` prints the current watcher state from `%LOCALAPPDATA%\RCN-FPVSkyDive\state\bridge.json`; `diagnose` prints the native runtime, DJI PnP interfaces, and log location. `start` and `stop` manage the watcher, which owns a Windows named mutex so duplicate bridge instances are rejected. `self-test` creates an Xbox target, briefly updates one axis, then sends a neutral report before dropping the target. `probe` only reads and validates stick frames. `bridge-smoke` runs the complete serial-to-Xbox path for two seconds, sends neutral output, and exits. `bridge` creates a virtual Xbox controller, sends neutral output before live values, and drops the target when the process ends. `watch` discovers the DJI Protocol COM interface and reconnects after a transport failure, but remains in `awaiting_live_verification` until the device-specific `verify-input` approval exists; no virtual controller is created before that gate. It currently implements the established Mode 2 mapping only and leaves all buttons untouched.

`open-fpv` detects Steam libraries and opens the installed FPV SkyDive app through Steam app `1278060`; it does not edit game files or bindings. `verify-input` is the guided four-axis live-stick check and auto-discovers the Protocol port unless `--port` is supplied; it never creates a virtual controller and exits nonzero if any axis does not visibly change. Its approval is tied to the persisted USB PnP instance ID, not the COM number, so reconnect/renumbering remains safe. The default mapping is stored in `%LOCALAPPDATA%\RCN-FPVSkyDive\state\mapping.conf`. Each Xbox axis supports `invert`, `deadzone`, `trim`, `saturation`, and `curve`; invalid values are clamped and buttons remain clear. `diagnose` also reports Windows, signed DJI driver records, live-frame probing, Steam detection, startup state, process identity, input-verification state, and the last 100 log lines.
