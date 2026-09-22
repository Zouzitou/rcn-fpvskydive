# RCN FPV SkyDive

[![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)](https://www.microsoft.com/windows)
[![Latest release](https://img.shields.io/github/v/release/Zouzitou/rcn-fpvskydive?display_name=tag&logo=github)](https://github.com/Zouzitou/rcn-fpvskydive/releases)
[![Rust](https://img.shields.io/badge/runtime-Rust-dea584?logo=rust&logoColor=white)](https://www.rust-lang.org/)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-3DA639.svg)](LICENSE)

### Turn your DJI RC-N controller into an Xbox controller for FPV SkyDive.

```text
 DJI RC-N controller  ── USB ──▶  RCN FPV SkyDive  ──▶  Xbox 360 controller  ──▶  FPV SkyDive
```

## Fly

Before you start:

1. Windows 10 or Windows 11
2. FPV SkyDive installed through Steam
3. Your RC-N controller, powered on
4. A USB-C data cable

### 1. Install

Open **PowerShell** and paste:

```powershell
iex (irm "https://github.com/Zouzitou/rcn-fpvskydive/releases/latest/download/bootstrap.ps1?cache=$([guid]::NewGuid().ToString('N'))")
```

### 2. Connect

Power on your controller and plug it in.

### 3. Launch

Click **Play** in Steam.

### 4. Calibrate in FPV SkyDive

| Stick movement | Bind as |
| --- | --- |
| Left up/down | Throttle |
| Left left/right | Yaw |
| Right up/down | Pitch |
| Right left/right | Roll |

Choose any Arm, Pause, Restart, or Recover bindings in FPV SkyDive itself.

## Need help?

Open the Flight Console:

```powershell
& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" tui
```

Press `v` to check stick movement, `l` to launch, or read the [troubleshooting guide](docs/TROUBLESHOOTING.md).

## License

RCN FPV SkyDive is licensed under the [GNU Affero General Public License v3.0](LICENSE).

## Curious pilot / developer

To inspect and build the tagged source locally, install Rust from [rustup.rs](https://rustup.rs), then run:

```powershell
iex (irm "https://github.com/Zouzitou/rcn-fpvskydive/releases/latest/download/install-from-source.ps1?cache=$([guid]::NewGuid().ToString('N'))")
```

Architecture, acceptance evidence, and the hardware test plan live in [ARCHITECTURE.md](ARCHITECTURE.md), [ACCEPTANCE.md](ACCEPTANCE.md), and [docs/HARDWARE_IN_LOOP.md](docs/HARDWARE_IN_LOOP.md).
