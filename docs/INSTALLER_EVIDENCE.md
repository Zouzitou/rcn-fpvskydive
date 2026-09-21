# Installer evidence

This file records checks performed against the shipped payload rather than only the source tree.

## v0.1.28 on Windows 11

- Bootstrap source: `v0.1.28/bootstrap.ps1`
- Installation root: `%LOCALAPPDATA%\RCN-FPVSkyDive`
- Runtime: native Rust `rcn-bridge.exe` 0.1.28
- Login startup: disabled; `state/startup.json` reports `steam-launch-wrapper`
- Mapping file: created at `state/mapping.conf`
- ViGEm self-test: passed; neutral cleanup update sent
- Diagnostics: Protocol interface `DEVICE USB VCOM For Protocol (COM12)` selected; Debug COM11 also present and not selected; 13 valid live frames observed
- Lifecycle: native `start` followed by `stop` returned success and left no watcher process
- Wrapper lifecycle: `launch-fpv.ps1 cmd.exe /d /c exit 0` returned exit code 0, wrote `state/bridge.json` as `stopped`, and left zero watcher processes

The wrapper check uses a harmless local process as a stand-in for Steam because Steam/FPV SkyDive is not installed on this validation host. Actual Steam launch and in-game calibration remain manual gates.

## Not yet proven

- RC-N2 and RC-N3 hardware and firmware behavior
- Clean-machine driver installation with an official DJI INF
- Physical unplug/replug, sleep/resume, and COM renumbering on separate hardware runs
- Actual FPV SkyDive calibration and flight controls
