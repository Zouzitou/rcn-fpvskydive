# RCN FPV SkyDive

[![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![Latest release](https://img.shields.io/github/v/release/Zouzitou/rcn-fpvskydive?display_name=tag&logo=github)](https://github.com/Zouzitou/rcn-fpvskydive/releases)
[![Rust](https://img.shields.io/badge/runtime-Rust-dea584?logo=rust&logoColor=white)](https://www.rust-lang.org/)
[![No login startup](https://img.shields.io/badge/bridge-game--only-ff8c00)](README.md#fly)

### Turn your DJI RC-N controller into an Xbox controller for FPV SkyDive.

```text
 DJI RC-N controller  ── USB ──▶  RCN FPV SkyDive  ──▶  Xbox 360 controller  ──▶  FPV SkyDive
```

## Fly

**You need:** Windows 10/11 · FPV SkyDive on Steam · your powered-on RC-N controller · a USB-C data cable.

### 1 — Install

Open **PowerShell**, paste this, and wait for the orange completion screen:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/main/bootstrap.ps1 | iex
```

### 2 — Connect

Power on your controller and plug it in. The app checks for a healthy controller connection before creating the virtual Xbox controller.

### 3 — Launch

Click **Play** in Steam. The installer configures FPV SkyDive’s Steam entry to start the bridge with the game and close it when you exit.

### 4 — Calibrate in FPV SkyDive

| Stick movement | Bind as |
| --- | --- |
| Left up/down | Throttle |
| Left left/right | Yaw |
| Right up/down | Pitch |
| Right left/right | Roll |

Choose any Arm, Pause, Restart, or Recover bindings in FPV SkyDive itself.

If Steam is open during installation, setup waits in the background and safely updates FPV SkyDive’s launch option the next time Steam closes. You do not need to copy/paste launch options or rerun the installer. Existing FPV SkyDive launch arguments are preserved.

## Need help?

Open the Flight Console:

```powershell
& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" tui
```

Press `v` to check stick movement, `l` to launch, or read the [troubleshooting guide](docs/TROUBLESHOOTING.md). It never installs a driver or edits game bindings without you choosing to do so.

## Built for flying, not background clutter

| What it does | What it does not do |
| --- | --- |
| Starts the bridge with FPV SkyDive | Run at Windows login |
| Sends neutral sticks on disconnect or exit | Leave a stuck input behind |
| Verifies the downloaded release before installing | Print your Windows username during install |
| Keeps your game bindings under your control | Change settings behind your back |

## Curious pilot / developer

To inspect and build the tagged source locally, install Rust from [rustup.rs](https://rustup.rs), then run:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/main/install-from-source.ps1 | iex
```

Architecture, acceptance evidence, and the hardware test plan live in [ARCHITECTURE.md](ARCHITECTURE.md), [ACCEPTANCE.md](ACCEPTANCE.md), and [docs/HARDWARE_IN_LOOP.md](docs/HARDWARE_IN_LOOP.md).
