# RCN FPV SkyDive — agent guide

## Purpose

This repository turns a DJI RC-N controller into a virtual Xbox 360 controller for FPV SkyDive on Windows. Treat flight safety, truthful compatibility claims, and a frictionless pilot experience as the primary product requirements.

## Start here

- Read `README.md` for the pilot-facing flow.
- Read `ARCHITECTURE.md` before changing bridge, installer, or Steam-launch behavior.
- Check `git status --short` before editing. Preserve unrelated user changes.
- Use `rg` for code and text searches.

## Key constraints

- The native bridge is Rust in `rust-bridge/`; do not reintroduce a Python runtime.
- Do **not** run Python or `pytest` on this host: it crashes the user’s desktop client. Use the Rust and PowerShell checks below instead.
- Do **not** use GitHub Actions. Releases are built, tested, hashed, and published locally through `release.ps1`.
- Never claim a controller works just because of its name, VID/PID, or a serial port. The bridge must receive valid live input before it exposes Xbox controls.
- Keep neutral output on startup, disconnect, stale input, failure, and exit. Never invent in-game button bindings.
- The bridge runs only with FPV SkyDive. Do not add Windows-login bridge startup.
- Steam Play setup is scoped to FPV SkyDive, preserves existing launch arguments, and must be reversible by uninstall.

## Build and validation

Run the smallest relevant checks after changes:

```powershell
./verify-scripts.ps1
cargo test --manifest-path rust-bridge/Cargo.toml
cargo build --release --manifest-path rust-bridge/Cargo.toml
```

When a game session is not running, a release or installer change also needs the native `self-test`. Do not interrupt FPV SkyDive or an active bridge just to test it.

## Installer and documentation rules

- Keep `bootstrap.ps1` idempotent, per-user, SHA-256 verified, and free of usernames/absolute paths in normal console output.
- Keep the orange installer flow understandable to pilots. Do not stream compiler output, Python output, or raw internal paths in normal success output.
- The README is for drone pilots first. Keep its quick-start short, visual, and free from implementation detail; put deep technical material in `docs/` or architecture files.
- Do not silently install drivers or edit game bindings. Explain any needed user action plainly.

## Git, releases, and notes

- Before any commit or push, ensure Git is using `Zouzitou <204303365+Zouzitou@users.noreply.github.com>`.
- Use `release.ps1 -Version <version>` for releases. It updates versions, tests, packages locally, pushes, and publishes—no GitHub Actions.
- Before releasing, copy `RELEASE_NOTES_TEMPLATE.md` to `RELEASE_NOTES.md` and complete every section. The script rejects missing, placeholder-filled, or wrongly versioned notes.
- After publication, run `./verify-release.ps1` and verify the published release body when release-note behavior changed.

## Completion standard

Report what changed, what was actually verified, and any hardware limitation that remains. Do not present RC-N2/RC-N3 or in-game calibration as proven without direct evidence.
