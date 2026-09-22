# Acceptance matrix

| Area | Gate | Evidence |
|---|---|---|
| Install | One-line bootstrapper is repeatable | installer test transcript |
| Native runtime | Locally built Rust executable, no Python runtime | Cargo lockfile and release build |
| Driver | Explicit signed-INF validation, `pnputil` install, post-install rescan, and Protocol port | `driver.ps1` result + diagnostic report |
| Device | Protocol interface selected, Debug rejected | discovery tests + report |
| Gamepad | Virtual Xbox self-test passes and cleans up | self-test result |
| Bridge | Neutral startup, validated frames, reconnect, clean teardown, and singleton ownership | native integration result + mutex test + `bridge.json` |
| Mapping | Configurable inversion, dead zone, trim, saturation, and curve | native mapping tests + `mapping.conf` |
| Live input gate | Four-axis user movement required before watcher creates Xbox target | `verify-input` + `input-verification.json` |
| Diagnostics | OS, driver, port, live frames, startup, Steam, process, and 100 log lines | `diagnose` output |
| Flight console | Responsive native dashboard restores terminal on exit, shows live health, and gates unsafe actions | `tui` smoke test + manual action review |
| Steam launch | No login watcher; one bridge survives FPV SkyDive's Steam-to-game handoff and exits with the game | wrapper lifecycle test + v0.1.39 HIL evidence |
| SkyDive | Steam wrapper, game input selection, and normal controller calibration | RC-N1 in-game XInput detection and four-axis view recorded; calibration and normal Steam-wrapper launch/exit remain HIL gates |
| Safety | Unsupported PID rejected; no controller outside game session | native status and lifecycle tests |
| Release | Reproducible artifact, hash, uninstall, README | release checklist |
