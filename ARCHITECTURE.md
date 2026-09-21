# RCN FPV SkyDive architecture

## Scope and compatibility

The product is a per-user Windows application installed below `%LOCALAPPDATA%\\RCN-FPVSkyDive`. RC-N1 is the first protocol implementation. RC-N2 and RC-N3 are detected and reported, but remain unsupported until their USB protocol is positively characterized.

## Components

```text
bootstrap.ps1
  -> release-pinned artifact + SHA-256 verification
  -> bin/rcn-bridge.exe (native Rust runtime)
  -> startup.ps1 (per-user login registration)
  -> rcn-bridge watch (long-lived process)
       discovery -> transport -> protocol -> mapping -> gamepad
              \________________ lifecycle / diagnostics ________________/
```

- `discovery`: a bounded WMI query accepts only the RC-N1 (`VID_2CA3&PID_1020`) healthy `For Protocol` interface; Debug interfaces and unvalidated RC-N-family PIDs are not activated.
- `transport`: opens and owns the selected Protocol COM port, detects busy/debug/wrong-port states, and emits reconnect events.
- `protocol`: DuML framing, checksum validation, packet decoding, and live-frame timestamps. Unknown packets are retained as redacted counters, not printed continuously.
- `mapping`: the established RC-N1 Mode 2 four-axis mapping with all buttons left clear.
- `gamepad`: native ViGEm adapter with neutral-on-start, neutral-on-smoke-test exit, and target removal when a session ends.
- `lifecycle`: a per-user scheduled-task/Startup-folder launcher starts `watch`, which rediscovers after serial failure or unplug/replug.

## Data flow

1. The bridge starts neutral and enters `WAITING_FOR_CONTROLLER`.
2. Discovery scans USB/PnP state and ranks Protocol candidates deterministically. Debug interfaces are never accepted as setup success.
3. Transport opens the selected port and protocol validates frames. A port is not considered connected until valid live frames arrive.
4. Mapping transforms checksum-validated RC-N1 frames into Xbox 360 axes; output is neutral before the first valid frame.
5. Lifecycle drops the virtual target on an I/O failure, then rediscovers the Protocol interface after a short delay.

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
