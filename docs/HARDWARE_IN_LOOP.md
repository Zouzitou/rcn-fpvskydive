# Hardware-in-the-loop test plan

Run this plan on clean Windows 10 and Windows 11 machines. Record controller model, firmware version, cable, USB port, driver evidence, selected instance ID, selected Protocol port, and redacted diagnostic report.

RC-N1 evidence is recorded in [HARDWARE_EVIDENCE_RC_N1.md](HARDWARE_EVIDENCE_RC_N1.md) and [INSTALLER_EVIDENCE.md](INSTALLER_EVIDENCE.md). Checked boxes below are specific to that controller and Windows 11 host; unchecked cases remain required before claiming broader support.

## Per-controller matrix

| Test | RC-N1 | RC-N2 | RC-N3 | Required result |
|---|---:|---:|---:|---|
| Controller powered and data cable | [x] | [ ] | [ ] | Positive USB identity and interface evidence |
| Charge-only cable / wrong controller port | [ ] | [ ] | [ ] | Precise remediation; never READY |
| Missing VCOM driver | [ ] | [ ] | [ ] | Verified driver flow or actionable failure |
| DJI Assistant 2 open | [ ] | [ ] | [ ] | Busy/interference diagnosis and safe retry |
| Protocol + Debug interfaces | [x] | [ ] | [ ] | Protocol selected; Debug rejected |
| Plug after game bridge starts | [ ] | [ ] | [ ] | Waiting → connected after live verification |
| Unplug/replug and COM renumber | [ ] | [ ] | [ ] | Re-resolve instance ID and reconnect |
| Sleep/resume | [ ] | [ ] | [ ] | Neutral during gap, reconnect after resume |
| Four-axis live verification | [x] | [ ] | [ ] | All axes change plausibly |
| Native guided verifier | [x] | [ ] | [ ] | `verify-input` passes all four axes |
| FPV SkyDive controller detection and default axis view | [x] | [ ] | [ ] | XInput Gamepad 1 and four stick axes visible; no bindings changed |
| FPV SkyDive calibration | [ ] | [ ] | [ ] | Mapping confirmed; Arm/Pause untouched |
| FPV game launch + bridge presence | [x] | [ ] | [ ] | Running game, connected bridge, and Xbox target verified together |
| Steam Library launch/exit | [ ] | [ ] | [ ] | Exactly one bridge while playing; none after game exit |
| Repair and uninstall | [ ] | [ ] | [ ] | Idempotent repair; reversible removal |

RC-N2 and RC-N3 remain `RC-N family unconfirmed` unless their Protocol interface passes the native three-frame checksum gate and the four-axis live-stick test. A USB name, PID, or successful serial open alone is never compatibility evidence.

The RC-N1 game-launch check used the live `game-check` verifier: it observed FPV SkyDive running, bridge state `connected`, continuously increasing mapped-frame count, and an `OK` Windows Xbox 360 controller. The launcher teardown is covered by the packaged wrapper lifecycle test; a physical Steam-Library launch/exit, unplug/replug, and sleep/resume remain unchecked.
