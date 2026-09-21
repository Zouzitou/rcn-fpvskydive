# RCN FPV SkyDive

Safe, per-user Windows bridge for DJI RC-N controllers and FPV SkyDive. It exposes validated controller input as a virtual Xbox 360 controller.

> Native runtime: [`rust-bridge/`](rust-bridge/) is the production bridge. The installer ships its locally built `rcn-bridge.exe`; it does not require Python, pip, or pytest.

> Status: RC-N1 is the validated native implementation. RC-N2 and RC-N3 are intentionally not activated until their Protocol interface and frame layout have independent hardware evidence; a name or USB vendor alone is not compatibility evidence.

## Design goals

- One PowerShell bootstrapper, isolated under `%LOCALAPPDATA%\\RCN-FPVSkyDive`.
- Protocol-port selection by positive USB/interface evidence; Debug ports are rejected.
- Neutral output on startup, stale data, reconnect, shutdown, and failed self-test.
- A locally built, SHA-256 verified native executable with no Python runtime dependency.

See [ARCHITECTURE.md](ARCHITECTURE.md), [ACCEPTANCE.md](ACCEPTANCE.md), and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Development

```powershell
cargo test --manifest-path rust-bridge/Cargo.toml
cargo build --release --manifest-path rust-bridge/Cargo.toml
```

## Installation

Run from a trusted checkout or a release-pinned URL in an elevated or non-elevated PowerShell terminal:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.18/bootstrap.ps1 | iex
```

The tagged bootstrapper downloads the release payload and verifies its SHA-256 before installation. It does not silently install an unverified driver.

## Commands

```powershell
$Bridge = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive\bin\rcn-bridge.exe'
& $Bridge status
& $Bridge self-test
& $Bridge probe --port COM12
& $Bridge bridge-smoke --port COM12
& $Bridge bridge-auto
```

`watch` is registered for login by the installer. It waits safely for the RC-N1 Protocol interface, reconnects after a disconnect, and removes the virtual controller whenever its active bridge session ends. `bridge-auto` is the interactive foreground command; end it with `Ctrl+C` after game calibration.

The installed uninstaller is available at `%LOCALAPPDATA%\RCN-FPVSkyDive\uninstall.ps1`.

## Driver and game setup

Mode 2 is the native mapping (left vertical throttle, left horizontal yaw, right vertical pitch, right horizontal roll). Install the official DJI VCOM driver if Windows does not expose `DEVICE USB VCOM For Protocol`. The bridge accepts only the RC-N1 `VID_2CA3&PID_1020` Protocol interface and never uses its Debug COM port. After `self-test` and `bridge-smoke` succeed, open FPV SkyDive normally and use its own controller-calibration screen; the bridge never edits game bindings.

## Security

The installer is per-user, release-pinned, and SHA-256 verified. It never installs drivers or edits FPV SkyDive settings; use an official DJI driver package and the game’s own calibration UI.
