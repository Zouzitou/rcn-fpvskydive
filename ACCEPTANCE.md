# Acceptance matrix

| Area | Gate | Evidence |
|---|---|---|
| Install | One-line bootstrapper is repeatable | installer test transcript |
| Native runtime | Locally built Rust executable, no Python runtime | Cargo lockfile and release build |
| Driver | Matching signed Ports driver and post-install rescan | diagnostic report |
| Device | Protocol interface selected, Debug rejected | discovery tests + report |
| Gamepad | Virtual Xbox self-test passes and cleans up | self-test result |
| Bridge | Neutral startup, validated frames, reconnect, clean teardown | native integration result + `bridge.json` |
| Steam launch | No login watcher; one bridge for FPV SkyDive only | wrapper start/exit test |
| SkyDive | Steam wrapper and normal controller calibration | manual HIL checklist |
| Safety | Unsupported PID rejected; no controller outside game session | native status and lifecycle tests |
| Release | Reproducible artifact, hash, uninstall, README | release checklist |
