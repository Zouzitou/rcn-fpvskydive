# RCN FPV SkyDive v0.1.59

## Highlights

- Driver installation now validates the official Windows driver-package trust boundary correctly: the DJI INF must reference a present, valid catalog signed by DJI or a trusted Microsoft hardware publisher before the installer can request UAC or call `pnputil`.
- Driver packages with a missing catalog, unsafe catalog path, invalid signature, non-DJI signer, wrong provider, or wrong DJI USB vendor ID are rejected before installation.

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
