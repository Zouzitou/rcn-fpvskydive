# RCN FPV SkyDive architecture

## Scope and compatibility

The product is a per-user Windows application installed below `%LOCALAPPDATA%\\RCN-FPVSkyDive`. RC-N1 is the first protocol implementation. RC-N2 and RC-N3 are detected and reported, but remain unsupported until their USB protocol is positively characterized.

## Components

```text
bootstrap.ps1
  -> signed/release-pinned artifact + SHA-256 verification
  -> app/installer (state machine, elevation boundary, repair/uninstall)
  -> app/bridge (long-lived process)
       discovery -> transport -> protocol -> mapping -> gamepad
              \________________ lifecycle / diagnostics ________________/
```

- `discovery`: SetupAPI/WMI and `serial.tools.list_ports`; ranks only positively identified DJI-compatible Protocol interfaces and records hardware instance IDs.
- `transport`: opens and owns the selected Protocol COM port, detects busy/debug/wrong-port states, and emits reconnect events.
- `protocol`: DuML framing, checksum validation, packet decoding, and live-frame timestamps. Unknown packets are retained as redacted counters, not printed continuously.
- `mapping`: calibration, center trim, dead zone, saturation, inversion, response curves, and explicit transmitter-mode profiles.
- `gamepad`: ViGEm/vgamepad adapter with neutral-on-start, neutral-on-error, button release, and non-destructive self-test guarantees.
- `lifecycle`: single-instance guard, startup idle state, device hotplug/reconnect, suspend/resume recovery, watchdog backoff, and shutdown cleanup.
- `diagnostics`: structured JSONL logs, redacted report generation, health state, and human-readable exit categories.

## Data flow

1. The bridge starts neutral and enters `WAITING_FOR_CONTROLLER`.
2. Discovery scans USB/PnP state and ranks Protocol candidates deterministically. Debug interfaces are never accepted as setup success.
3. Transport opens the selected port and protocol validates frames. A port is not considered connected until valid live frames arrive.
4. A guided verifier asks for movement of each configured axis and requires plausible changing values.
5. Mapping transforms calibrated DJI values into Xbox 360 axes; output is rate-limited and remains neutral when frames become stale.
6. Lifecycle monitors unplug/replug, COM-number changes, sleep/resume, process ownership, and gamepad health.
7. Diagnostics persist selected port, instance ID, driver evidence, packet/frame counters, PID, and current state with usernames and absolute paths redacted in exports.

## Installer state machine

```text
DISCOVER -> PLAN -> FETCH_VERIFIED -> PREPARE_ENV -> DRIVER_GATE
    -> RESCAN -> GAMEPAD_SELF_TEST -> STARTUP_REGISTER -> STARTUP_TEST
    -> HARDWARE_GUIDE -> STABILITY_CHECK -> READY

Any state -> REPAIRABLE_FAILURE -> DIAGNOSE
READY -> UNINSTALL -> REMOVED
```

The installer is idempotent. Elevation is requested only for driver-store operations or machine-level actions, with an explanation. Each transition records a state file and can resume or repair without duplicating processes or startup entries. `READY` is withheld unless virtual gamepad self-test, Protocol-port selection, live-stick verification, short stability, and startup test all pass.

## Acceptance tests

### Automated

- Candidate ranking prefers `For Protocol` over `For Debug`, never hard-codes COM numbers, and persists/resolves instance IDs.
- Supported/unsupported VID/PID/interface combinations are classified correctly.
- DuML frames parse valid packets and reject bad length/checksum/truncated input.
- Mapping covers neutral, inversion, trim, dead zone, saturation, curves, and configured transmitter modes.
- Disconnect/reconnect and COM renumbering return to connected state with neutral output during gaps.
- Duplicate bridge startup is rejected and leaves exactly one owner.
- Self-test always releases axes/buttons and reports cleanup failures.
- Diagnostic exports redact usernames and machine-specific paths.

### Hardware-in-the-loop

For each RC-N1, RC-N2, and RC-N3 sample: cold boot, wrong cable/port, DJI Assistant open, driver absent/present, Protocol vs Debug exposure, plug after startup, unplug/replug, COM renumber, sleep/resume, live four-axis verification, FPV SkyDive calibration, reboot startup, repair, and uninstall. RC-N2/RC-N3 must explicitly produce `unsupported pending protocol implementation` unless a validated protocol decoder is present.

## Security boundaries

Downloads are release-pinned and hash-checked. Driver installation accepts only verified, matching, signed/provider-validated packages and uses `pnputil`. No arbitrary INF is selected. Logs contain operational metadata only; diagnostic bundles redact identity and local paths. The bridge never edits FPV SkyDive settings blindly while the game is running.
