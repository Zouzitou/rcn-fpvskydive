# RCN FPV SkyDive

Safe, per-user Windows bridge for DJI RC-N controllers and FPV SkyDive. It exposes validated controller input as a virtual Xbox 360 controller.

> Native runtime: [`rust-bridge/`](rust-bridge/) is the production bridge. The installer ships its locally built `rcn-bridge.exe`; it does not require Python, pip, or pytest.

> Status: RC-N1 is hardware-validated. RC-N2 and RC-N3 may enter the same native bridge only after their healthy DJI Protocol interface returns three checksum-valid 38-byte stick frames; the virtual Xbox controller is not created before that gate passes. A name or USB vendor alone is never compatibility evidence.

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
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.34/bootstrap.ps1 | iex
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

The bridge never starts at Windows login. In Steam, open **FPV SkyDive → Properties → General → Launch Options** and paste this one-time setting:

```text
cmd.exe /d /c call "%LOCALAPPDATA%\RCN-FPVSkyDive\launch-fpv.cmd" %command%
```

Steam then starts the bridge immediately before FPV SkyDive and the wrapper stops that exact bridge process when the game exits. `bridge-auto` remains the interactive foreground command for diagnostics; end it with `Ctrl+C` after game calibration.

The installed uninstaller is available at `%LOCALAPPDATA%\RCN-FPVSkyDive\uninstall.ps1`. The native `open-fpv` command detects Steam libraries and opens FPV SkyDive through Steam without modifying game files.

## Driver and game setup

Mode 2 is the native default mapping (left vertical throttle, left horizontal yaw, right vertical pitch, right horizontal roll). Axis inversion, dead zone, center trim, saturation, and response curve can be edited in `%LOCALAPPDATA%\RCN-FPVSkyDive\state\mapping.conf`; restart the game wrapper after changing it. Install the official DJI VCOM driver if Windows does not expose `DEVICE USB VCOM For Protocol`. The packaged `driver.ps1` supports a deliberate validated install when you provide the official INF: `powershell -File "$env:LOCALAPPDATA\RCN-FPVSkyDive\driver.ps1" -Action install -InfPath C:\path\dji_vcom_driver11.inf`. It rejects unsigned INFs and packages without `VID_2CA3`, requests UAC only for `pnputil`, rescans, and requires the Protocol interface to appear. The bridge never uses a Debug COM port. RC-N1 is proven on `VID_2CA3&PID_1020`; other RC-N-family Protocol interfaces are fail-closed until they complete the checksum/live-frame gate. After `self-test` and `bridge-smoke`, run `& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" verify-input` and move each stick continuously while its prompt is waiting, then press Enter; it auto-discovers the current Protocol port. Then open FPV SkyDive normally and use its own controller-calibration screen; the bridge never edits game bindings.

## Security

The installer is per-user, release-pinned, and SHA-256 verified. It never installs a driver implicitly or edits FPV SkyDive settings; use the explicit driver flow with an official DJI package and the game’s own calibration UI.
