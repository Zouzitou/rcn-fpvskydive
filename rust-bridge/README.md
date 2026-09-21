# Native Rust bridge

`rcn-bridge` is the production native runtime. It uses the RC-N1 hardware-verified DuML enable/poll sequence and creates a ViGEm Xbox 360 target without Python.

```powershell
cargo test --manifest-path rust-bridge/Cargo.toml
cargo run --manifest-path rust-bridge/Cargo.toml -- status
cargo run --manifest-path rust-bridge/Cargo.toml -- self-test
cargo run --manifest-path rust-bridge/Cargo.toml -- probe --port COM12
cargo run --manifest-path rust-bridge/Cargo.toml -- bridge-smoke --port COM12
cargo run --manifest-path rust-bridge/Cargo.toml -- bridge --port COM12
```

`status` prints the current watcher state from `%LOCALAPPDATA%\RCN-FPVSkyDive\state\bridge.json`. `self-test` creates an Xbox target, briefly updates one axis, then sends a neutral report before dropping the target. `probe` only reads and validates stick frames. `bridge-smoke` runs the complete serial-to-Xbox path for two seconds, sends neutral output, and exits. `bridge` creates a virtual Xbox controller, sends neutral output before live values, and drops the target when the process ends. `watch` discovers the RC-N1 Protocol COM interface and reconnects after a transport failure. It currently implements the established Mode 2 mapping only and leaves all buttons untouched.
