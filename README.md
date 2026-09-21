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

## Tutorial: from install to first flight

### 1. Install the recommended verified release

Open **PowerShell** (not necessarily as administrator), paste this one line, and wait for the completion message:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.48/bootstrap.ps1 | iex
```

This is the recommended route. The tagged bootstrapper downloads a fixed release payload and verifies its SHA-256 before it writes anything to your per-user installation. Its orange installer screen shows only friendly progress—not your Windows username or absolute local paths—and it never silently installs a driver.

### 2. Optional: build it locally from readable source

If you would rather inspect the tagged source and compile the bridge on your own PC, install the stable Rust toolchain from [rustup.rs](https://rustup.rs), reopen PowerShell, then paste:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.48/install-from-source.ps1 | iex
```

The source installer prints five clear stages: Rust check, source download, local optimized build, install, and virtual-Xbox verification. Compiler details and inspection files stay private on the machine instead of being streamed into the console. It does not use Python, pip, pytest, GitHub Actions, or an automatic driver install. The release installer above remains the better choice when you want the fixed SHA-256-verified package instead.

### 3. Launch the game with the bridge

Plug in and power on the RC-N1, then click **Start Menu → RCN FPV SkyDive**. The launcher starts the virtual Xbox bridge, waits for it to be ready, launches FPV SkyDive, and stops that exact bridge after the game exits. It never runs at Windows login.

For Steam Library launches instead, open **FPV SkyDive → Properties → General → Launch Options** and paste this one-time setting:

```text
cmd.exe /d /c call "%LOCALAPPDATA%\RCN-FPVSkyDive\launch-fpv.cmd" %command%
```

### 4. Verify your sticks once

Use the Flight Console before your first flight:

```powershell
& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" tui
```

Choose **Verify sticks** (or press `v`). Move the prompted stick through its range while the prompt waits, then press Enter. After all four axes pass, open FPV SkyDive’s own controller-calibration screen and bind the axes there. The bridge deliberately leaves Arm, Pause, Restart, and Recover bindings alone.

### 5. Fly, then check health if anything looks wrong

In the console, `l` launches FPV SkyDive and `g` runs the read-only game check. A healthy session shows **Bridge connected**, **Virtual Xbox ready**, and **FPV SkyDive running**. If Windows has no `DEVICE USB VCOM For Protocol` port, use the deliberate official-driver flow in the next section; do not use the Debug port.

## Commands

```powershell
$Bridge = Join-Path $env:LOCALAPPDATA 'RCN-FPVSkyDive\bin\rcn-bridge.exe'
& $Bridge status
& $Bridge self-test
& $Bridge probe --port COM12
& $Bridge bridge-smoke --port COM12
& $Bridge bridge-auto
```

`bridge-auto` remains the interactive foreground command for diagnostics; end it with `Ctrl+C` after game calibration.

While FPV SkyDive is open, `& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" game-check` provides one read-only proof that the game process, connected bridge, and Windows Xbox controller are all present.

The installed uninstaller is available at `%LOCALAPPDATA%\RCN-FPVSkyDive\uninstall.ps1`. The native `open-fpv` command detects Steam libraries and opens FPV SkyDive through Steam without modifying game files.

## Driver and game setup

Mode 2 is the native default mapping (left vertical throttle, left horizontal yaw, right vertical pitch, right horizontal roll). Axis inversion, dead zone, center trim, saturation, and response curve can be edited in `%LOCALAPPDATA%\RCN-FPVSkyDive\state\mapping.conf`; restart the game wrapper after changing it. Install the official DJI VCOM driver if Windows does not expose `DEVICE USB VCOM For Protocol`. The packaged `driver.ps1` supports a deliberate validated install when you provide the official INF: `powershell -File "$env:LOCALAPPDATA\RCN-FPVSkyDive\driver.ps1" -Action install -InfPath C:\path\dji_vcom_driver11.inf`. It rejects unsigned INFs and packages without `VID_2CA3`, requests UAC only for `pnputil`, rescans, and requires the Protocol interface to appear. The bridge never uses a Debug COM port. RC-N1 is proven on `VID_2CA3&PID_1020`; other RC-N-family Protocol interfaces are fail-closed until they complete the checksum/live-frame gate. After `self-test` and `bridge-smoke`, run `& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" verify-input` and move each stick continuously while its prompt is waiting, then press Enter; it auto-discovers the current Protocol port. Then open FPV SkyDive normally and use its own controller-calibration screen; the bridge never edits game bindings.

## Security

The installer is per-user, release-pinned, and SHA-256 verified. It never installs a driver implicitly or edits FPV SkyDive settings; use the explicit driver flow with an official DJI package and the game’s own calibration UI.

## Flight console

Run the native dashboard any time from PowerShell:

```powershell
& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" tui
```

The console auto-refreshes bridge, live-verification, Xbox-target, and FPV SkyDive session health every two seconds. Use `↑/↓` or `j/k` to navigate, `Enter` to choose an action, `l` to launch, `g` to run the read-only game check, `v` to begin stick verification, `d` for redacted diagnostics, `m` to edit the mapping file, `r` to refresh, and `q` to quit. It disables unsafe actions during an active flight session and asks before stopping a bridge.
