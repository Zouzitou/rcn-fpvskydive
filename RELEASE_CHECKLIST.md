# Release checklist

- [ ] Build from a clean checkout with pinned dependencies.
- [ ] Generate SHA-256 manifest and sign release artifacts.
- [ ] Verify first install, repair, reboot/login startup, and uninstall.
- [ ] Verify unplug/replug, COM renumbering, sleep/resume, and duplicate-process prevention.
- [ ] Verify wrong-port/debug-only detection and DJI Assistant 2 interference guidance.
- [ ] Verify RC-N1 hardware live-stick flow.
- [ ] Run RC-N2 and RC-N3 detection; report unsupported protocol unless validated.
- [ ] Verify virtual gamepad self-test cleanup and no stuck axes/buttons.
- [ ] Produce a redacted diagnostic bundle and review logs for secrets.
- [ ] Publish only after README URLs, signatures, hashes, and rollback instructions are complete.
- [ ] Run `./release.ps1 -Version 0.1.3` locally; it runs tests, packages the allowlist, updates the bootstrap hash, commits/pushes, and publishes with `gh release create`. GitHub Actions is intentionally not used.
