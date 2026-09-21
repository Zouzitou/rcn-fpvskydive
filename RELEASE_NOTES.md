# RCN FPV SkyDive v0.1.60

## Highlights

- The bridge now makes an explicit neutral Xbox-stick update on every runtime exit path after the virtual controller is created, including a transport or output error.
- Driver installation continues to validate the official Windows driver-package trust boundary before UAC or `pnputil`.
- The Rust package metadata now correctly declares the project’s AGPLv3 license.

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
