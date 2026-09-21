# Hardware-in-the-loop test plan

Run this plan on clean Windows 10 and Windows 11 machines. Record controller model, firmware version, cable, USB port, driver evidence, selected instance ID, selected Protocol port, and redacted diagnostic report.

## Per-controller matrix

| Test | RC-N1 | RC-N2 | RC-N3 | Required result |
|---|---:|---:|---:|---|
| Controller powered and data cable | [ ] | [ ] | [ ] | Positive USB identity and interface evidence |
| Charge-only cable / wrong controller port | [ ] | [ ] | [ ] | Precise remediation; never READY |
| Missing VCOM driver | [ ] | [ ] | [ ] | Verified driver flow or actionable failure |
| DJI Assistant 2 open | [ ] | [ ] | [ ] | Busy/interference diagnosis and safe retry |
| Protocol + Debug interfaces | [ ] | [ ] | [ ] | Protocol selected; Debug rejected |
| Plug after bridge startup | [ ] | [ ] | [ ] | Waiting → connected after live verification |
| Unplug/replug and COM renumber | [ ] | [ ] | [ ] | Re-resolve instance ID and reconnect |
| Sleep/resume | [ ] | [ ] | [ ] | Neutral during gap, reconnect after resume |
| Four-axis live verification | [ ] | [ ] | [ ] | All axes change plausibly |
| FPV SkyDive calibration | [ ] | [ ] | [ ] | Mapping confirmed; Arm/Pause untouched |
| Login/reboot startup | [ ] | [ ] | [ ] | Exactly one bridge process and health update |
| Repair and uninstall | [ ] | [ ] | [ ] | Idempotent repair; reversible removal |

RC-N2 and RC-N3 remain `RC-N family unconfirmed` unless their Protocol interface passes checksum validation and the four-axis live-stick test. A USB name, PID, or successful serial open alone is never compatibility evidence.
