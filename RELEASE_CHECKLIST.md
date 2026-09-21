# Release checklist

- [ ] Build from a clean checkout with pinned dependencies.
- [ ] Run `./verify-scripts.ps1` and resolve any PowerShell syntax errors.
- [ ] Generate and review the SHA-256 manifest for the deterministic allowlisted release artifact.
- [ ] Verify first install, Steam launch-wrapper startup/shutdown, and uninstall.
- [ ] Verify unplug/replug, COM renumbering, sleep/resume, and duplicate-process prevention.
- [ ] Verify wrong-port/debug-only detection and DJI Assistant 2 interference guidance.
- [ ] Verify RC-N1 hardware live-stick flow.
- [ ] Run RC-N2 and RC-N3 detection; report unsupported protocol unless validated.
- [ ] Verify virtual gamepad self-test cleanup and no stuck axes/buttons.
- [ ] Verify `startup.ps1 -Action install` leaves no login watcher, then test the Steam launch wrapper starts one bridge for the game and removes it after game exit.
- [ ] With an official DJI INF, run `driver.ps1 -Action install -InfPath ...`; verify signature rejection, UAC, rescan, and Protocol-port postcondition.
- [ ] Produce a redacted diagnostic bundle and review logs for secrets.
- [ ] Publish only after README URLs, signatures, hashes, and rollback instructions are complete.
- [ ] Run `./release.ps1 -Version <version>` locally; it runs tests, packages the allowlist, updates the bootstrap hash, commits/pushes, and publishes with `gh release create`. GitHub Actions is intentionally not used.
- [ ] Run `./verify-release.ps1` after publication and confirm the downloaded payload matches the bootstrapper hash.
