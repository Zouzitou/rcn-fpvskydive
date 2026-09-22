# RCN FPV SkyDive v0.1.68

## Highlights

- Fixed the public one-line installer URLs to follow the repository's actual `master` default branch instead of a nonexistent `main` branch.

- The bridge now makes an explicit neutral Xbox-stick update on every runtime exit path after the virtual controller is created, including a transport or output error.
- Driver installation continues to validate the official Windows driver-package trust boundary before UAC or `pnputil`.
- The Rust package metadata now correctly declares the project’s AGPLv3 license.
- Repeated transport failures now use a bounded reconnect delay instead of retrying in a rapid loop.
- Steam launch no longer blocks FPV SkyDive on a controller that is powered off; the watcher stays alive and connects when the controller is turned on during the game.
- The `repair` command now performs a verified reinstall of its pinned release payload instead of only repairing launcher state.
- Removed the unused Python bridge and pytest suite so the public source tree matches the shipped native Rust runtime.
- Added native-tested deterministic Protocol-port ranking: Debug ports are rejected and COM numbers are discovered, never assumed.
- Redacted diagnostics now hide arbitrary local drive paths, including Steam libraries outside the user profile.
- Recorded RC-N1 in-game evidence: FPV SkyDive detects the bridge as XInput Gamepad 1 with the four standard stick axes.
- If Steam is open during install, the queued setup worker now covers an FPV SkyDive session immediately while it waits to apply the persistent Steam setting safely.

## Flight notes

- The app checks for a healthy live controller connection before creating the virtual Xbox controller.
- The bridge starts only with FPV SkyDive, never at Windows login, and never changes game bindings automatically.
- If Steam is open, a short-lived one-shot worker completes the scoped Steam setup after Steam exits; an existing FPV SkyDive launch argument is preserved.

## Verification

- PowerShell script parsing passed.
- Rust unit tests passed.
- Native virtual Xbox self-test passed with neutral cleanup.
- The published release ZIP is SHA-256 verified against the bootstrapper after publication.

## Install or update

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/master/bootstrap.ps1 | iex
```
