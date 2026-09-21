# Acceptance matrix

| Area | Gate | Evidence |
|---|---|---|
| Install | One-line bootstrapper is repeatable | installer test transcript |
| Native runtime | Locally built Rust executable, no Python runtime | Cargo lockfile and release build |
| Driver | Matching signed Ports driver and post-install rescan | diagnostic report |
| Device | Protocol interface selected, Debug rejected | discovery tests + report |
| Gamepad | Virtual Xbox self-test passes and cleans up | self-test result |
| Bridge | Neutral startup, live verification, reconnect, singleton | integration tests + JSONL log |
| Startup | Task/Startup fallback tested immediately | startup test result |
| SkyDive | Installation detection and guided calibration | manual HIL checklist |
| Safety | No false READY state; redacted diagnostics | state-machine tests |
| Release | Reproducible artifact, hash, uninstall, README | release checklist |
