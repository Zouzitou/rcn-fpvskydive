# RCN FPV SkyDive v0.1.58

## Highlights

- The README is now a compact visual flight page with GitHub badges, a controller-to-game signal-flow graphic, and a four-step pilot quick-start.
- It refers to your DJI RC-N controller naturally instead of leading with implementation and model-status detail.
- The installer now configures FPV SkyDive’s normal Steam Play button to start the bridge automatically.
- The README now uses shareable “latest installer” commands, so a command posted today installs the current release later too.
- The project is now explicitly licensed under GNU AGPLv3.
- Added a shared project instruction contract for Codex, Claude, and Gemini contributors.
- The release-note template and mandatory release-note checks remain in place for every future release.

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
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/main/bootstrap.ps1 | iex
```
