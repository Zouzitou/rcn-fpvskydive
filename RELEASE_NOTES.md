# RCN FPV SkyDive v0.1.82

## Highlights

- The installer now distinguishes a completed setup from a setup waiting for Steam to close once.
- The installer banner and PowerShell-facing text are ASCII-only, avoiding garbled characters in Windows PowerShell 5.1.
- Steam setup failures now say that attention is needed instead of claiming installation is complete.
- Windows controller detection keeps its localized-name matching without embedding non-ASCII PowerShell source text.

## Flight notes

- No controller mapping or game binding behavior changed in this release.
- The bridge still starts only with FPV SkyDive and begins with neutral Xbox controls.

## Verification

- All 13 Rust unit tests passed.
- A Rust release build and live virtual-Xbox self-test passed.
- The published binary and source ZIPs will be SHA-256 verified after publication.

## Install or update

```powershell
irm https://github.com/Zouzitou/rcn-fpvskydive/releases/latest/download/bootstrap.ps1 | iex
```
