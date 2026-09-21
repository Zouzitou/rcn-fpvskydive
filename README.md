# RCN FPV SkyDive

Safe, per-user Windows bridge for DJI RC-N controllers and FPV SkyDive. It exposes validated controller input as a virtual Xbox 360 controller.

> Status: early production scaffold. RC-N1 USB discovery and core safety primitives are implemented; driver installation, live DuML decoding, ViGEm validation, and RC-N2/RC-N3 protocol support require hardware validation before a release can claim `READY`.

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
```

The installed uninstaller is also available at `%LOCALAPPDATA%\RCN-FPVSkyDive\uninstall.ps1`.

Configure Mode 2 defaults or a specific virtual axis without editing files by hand:

```powershell
rcn-fpv config
rcn-fpv config --mode mode2 --axis left_y --invert off --dead-zone 0.03
```

`rcn-fpv repair` restores the managed local package and current-user startup registration. It does not install or replace device drivers. If the managed environment itself is missing, rerun the release-pinned bootstrap command.

`rcn-fpv driver-install` displays a UAC prompt and accepts only an existing `.inf` from the managed `drivers` folder. Put a verified official DJI driver package there first. The command rechecks that the active driver is DJI-provided, signed, Ports-class, and matches the RC-N1 hardware before it reports success.

## Security

Driver installation is an explicit, elevated operation and must verify provider, signature, and matching hardware IDs before `pnputil`. Diagnostic exports redact user names and absolute paths. No game configuration is edited while FPV SkyDive is running.
