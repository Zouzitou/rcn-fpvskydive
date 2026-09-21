# RCN FPV SkyDive v0.1.52

## Highlights

- The README is now a pilot-first flight card: install, connect the RC-N1, launch FPV SkyDive, calibrate, then troubleshoot only if needed.
- Both installers use the clean orange five-stage screen without streaming Windows user paths or Cargo compiler output.
- Every future release now requires useful release notes rather than a generic one-line description.

## Flight notes

- RC-N1 remains the only hardware-validated controller. RC-N2 and RC-N3 are detected safely but remain unsupported until their real protocol has been tested.
- The bridge still starts only with FPV SkyDive, never at Windows login, and never changes game bindings automatically.

## Verification

- PowerShell script parsing passed.
- Rust unit tests passed.
- Native virtual Xbox self-test passed with neutral cleanup.
- The published release ZIP is SHA-256 verified against the bootstrapper after publication.

## Install or update

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.52/bootstrap.ps1 | iex
```
