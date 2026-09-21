# RCN FPV SkyDive architecture

## Scope and compatibility

The product is a per-user Windows application installed below `%LOCALAPPDATA%\\RCN-FPVSkyDive`. RC-N1 is the first protocol implementation. RC-N2 and RC-N3 are detected and reported, but remain unsupported until their USB protocol is positively characterized.

## Components

```text
bootstrap.ps1
  -> release-pinned artifact + SHA-256 verification
  -> bin/rcn-bridge.exe (native Rust runtime)
  -> launch-fpv.cmd (Steam launch wrapper)
  -> rcn-bridge watch (only while FPV SkyDive runs)
       discovery -> transport -> protocol -> mapping -> gamepad
              \________________ lifecycle / diagnostics ________________/
```

- `discovery`: a bounded WMI query finds healthy DJI `For Protocol` interfaces. Every candidate, including RC-N2/RC-N3, must yield three checksum-valid 38-byte live-stick frames before the Xbox target is created; Debug interfaces are never activated. `driver.ps1` separately validates an explicitly supplied signed INF, checks `VID_2CA3`, invokes `pnputil` only after UAC approval, rescans, and requires the Protocol interface afterward.
- `transport`: opens and owns the selected Protocol COM port, detects busy/debug/wrong-port states, and emits reconnect events.
- `protocol`: DuML framing, checksum validation, packet decoding, and live-frame timestamps. Unknown packets are retained as redacted counters, not printed continuously.
- `mapping`: the established RC-N1 Mode 2 four-axis mapping with per-axis inversion, dead zone, trim, saturation, and response curve loaded from the managed state file; all buttons remain clear.
- `gamepad`: native ViGEm adapter with neutral-on-start, neutral-on-smoke-test exit, and target removal when a session ends.
- `lifecycle`: Steam's launch wrapper starts `watch` with FPV SkyDive, which rediscovers after serial failure or unplug/replug, persists the selected PnP instance ID, and remains neutral/awaiting until the device-specific four-axis live-input approval exists. Approval follows the PnP instance rather than a COM number, so a legitimate COM renumber does not invalidate it. It stops when the game process exits.

## Data flow

1. The bridge starts neutral and enters `WAITING_FOR_CONTROLLER`.
2. Discovery scans USB/PnP state and ranks Protocol candidates deterministically. Debug interfaces are never accepted as setup success.
3. Transport opens the selected port and protocol requires three checksum-valid live-stick frames. A port is not considered connected and no Xbox target exists until that gate passes.
4. Mapping transforms checksum-validated RC-N1 frames into Xbox 360 axes; output is neutral before the first valid frame.
5. Lifecycle drops the virtual target on an I/O failure, then rediscovers the Protocol interface after a short delay.

## Installer state machine

```text
DISCOVER -> PLAN -> FETCH_VERIFIED -> PREPARE_ENV -> GAMEPAD_SELF_TEST
    -> INSTALL_STEAM_LAUNCH_WRAPPER -> GAME_LAUNCH -> BRIDGE_RUNNING
    -> GAME_EXIT -> BRIDGE_STOPPED

Any state -> REPAIRABLE_FAILURE -> DIAGNOSE
READY -> UNINSTALL -> REMOVED
```

The installer is idempotent and has no login-start component. Steam starts the bridge only for FPV SkyDive, and the wrapper terminates that bridge on game exit. The virtual controller remains absent outside that session.

## Acceptance tests

### Automated

- Candidate ranking prefers `For Protocol` over `For Debug`, never hard-codes COM numbers, and persists/resolves instance IDs.
- Supported/unsupported VID/PID/interface combinations are classified correctly.
- DuML frames parse valid packets and reject bad length/checksum/truncated input.
- Mapping covers neutral, inversion, trim, dead zone, saturation, curves, and configured transmitter modes.
- Disconnect/reconnect and COM renumbering return to connected state with neutral output during gaps.
- Duplicate bridge startup is rejected by a Windows named mutex and leaves exactly one owner.
- Self-test always releases axes/buttons and reports cleanup failures.
- `diagnose` reports OS/runtime, signed driver records, Protocol port, live frames, startup state, Steam detection, process identity, mapping path, and the last 100 log lines. A redacted export remains a release gate.

### Hardware-in-the-loop

For each RC-N1, RC-N2, and RC-N3 sample: cold boot, wrong cable/port, DJI Assistant open, driver absent/present, Protocol vs Debug exposure, plug after startup, unplug/replug, COM renumber, sleep/resume, live four-axis verification, FPV SkyDive calibration, reboot startup, repair, and uninstall. RC-N2/RC-N3 must explicitly produce `unsupported pending protocol implementation` unless a validated protocol decoder is present.

## Security boundaries

Downloads are release-pinned and hash-checked. Driver installation accepts only verified, matching, signed/provider-validated packages and uses `pnputil`. No arbitrary INF is selected. Logs contain operational metadata only; diagnostic bundles redact identity and local paths. The bridge never edits FPV SkyDive settings blindly while the game is running.
