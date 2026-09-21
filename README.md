# RCN FPV SkyDive

Safe, per-user Windows bridge for DJI RC-N controllers and FPV SkyDive. It exposes validated controller input as a virtual Xbox 360 controller.

> Status: early production scaffold. RC-N1 USB discovery and core safety primitives are implemented. A DJI Protocol interface with an unrecognized RC-N-family PID is permitted only through the same checksum-validated, four-axis live-input gate; it is never labeled supported solely from its name or USB vendor. Hardware validation is still required before a release can claim `READY`.

## Design goals

- One PowerShell bootstrapper, isolated under `%LOCALAPPDATA%\\RCN-FPVSkyDive`.
- Protocol-port selection by positive USB/interface evidence; Debug ports are rejected.
- Neutral output on startup, stale data, reconnect, shutdown, and failed self-test.
- Pinned dependencies, structured diagnostics, idempotent repair, and explicit unsupported states.

See [ARCHITECTURE.md](ARCHITECTURE.md), [ACCEPTANCE.md](ACCEPTANCE.md), and [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Development

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.lock
.\.venv\Scripts\python.exe -m pytest -q
```

## Installation

Run from a trusted checkout or a release-pinned URL in an elevated or non-elevated PowerShell terminal:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.16/bootstrap.ps1 | iex
```

The tagged bootstrapper downloads the release payload and verifies its SHA-256 before installation. It does not silently install an unverified driver.

## Commands

```powershell
rcn-fpv status
rcn-fpv diagnose
rcn-fpv start
rcn-fpv stop
rcn-fpv repair
rcn-fpv uninstall
rcn-fpv driver-install --inf "$env:LOCALAPPDATA\RCN-FPVSkyDive\drivers\dji-vcom.inf"
rcn-fpv open-game
rcn-fpv calibrate
```

The installed uninstaller is also available at `%LOCALAPPDATA%\RCN-FPVSkyDive\uninstall.ps1`.

Mode 2 is the default (left vertical throttle, left horizontal yaw, right vertical pitch, right horizontal roll). Select Mode 1 or adjust a specific virtual axis without editing files by hand:

```powershell
rcn-fpv config
rcn-fpv config --mode mode1
rcn-fpv config --mode mode2 --axis left_y --invert off --dead-zone 0.03
```

`rcn-fpv repair` restores the managed local package and current-user startup registration. It does not install or replace device drivers. If the managed environment itself is missing, rerun the release-pinned bootstrap command.

Startup registration immediately checks for exactly one managed bridge watchdog and records the result in `%LOCALAPPDATA%\RCN-FPVSkyDive\state\startup.json`. A failed check is reported as a warning rather than pretending setup is ready.

`rcn-fpv driver-install` displays a UAC prompt and accepts only an existing `.inf` from the managed `drivers` folder. Put a verified official DJI driver package there first. The command rechecks that the active driver is DJI-provided, signed, Ports-class, and matches the RC-N1 hardware before it reports success.

`rcn-fpv open-game` opens the detected FPV SkyDive installation through Steam. It never changes the game’s bindings; use the game’s normal calibration screen after the virtual controller is confirmed.

`rcn-fpv calibrate` shows the next physical stick movement required by the bridge’s live-input verifier, plus the currently observed axes. Once all four axes are verified, it directs you to FPV SkyDive’s normal controller calibration screen and leaves game bindings untouched.

## Security

Driver installation is an explicit, elevated operation and must verify provider, signature, and matching hardware IDs before `pnputil`. Diagnostic exports redact user names and absolute paths. No game configuration is edited while FPV SkyDive is running.
