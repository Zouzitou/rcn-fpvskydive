# Native Rust bridge

`rcn-bridge` is the native replacement runtime in progress. It uses the RC-N1 hardware-verified DuML enable/poll sequence and creates a ViGEm Xbox 360 target without Python.

```powershell
cargo test --manifest-path rust-bridge/Cargo.toml
cargo run --manifest-path rust-bridge/Cargo.toml -- self-test
cargo run --manifest-path rust-bridge/Cargo.toml -- probe --port COM12
cargo run --manifest-path rust-bridge/Cargo.toml -- bridge-smoke --port COM12
cargo run --manifest-path rust-bridge/Cargo.toml -- bridge --port COM12
```

`self-test` creates an Xbox target, briefly updates one axis, then sends a neutral report before dropping the target. `probe` only reads and validates stick frames. `bridge-smoke` runs the complete serial-to-Xbox path for two seconds, sends neutral output, and exits. `bridge` creates a virtual Xbox controller, sends neutral output before live values, and drops the target when the process ends. It currently implements the established Mode 2 mapping only and leaves all buttons untouched. The installer does not use this crate until Cargo validation and hardware integration testing pass.
