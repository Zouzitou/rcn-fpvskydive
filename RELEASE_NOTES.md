# RCN FPV SkyDive v0.1.83

## Highlights

- The installer now keeps the four-stick check interactive instead of hiding its prompts.
- The stick check uses clear pilot-facing instructions and does not display raw diagnostic JSON during installation.
- The installer only reports completion after the setup flow has actually finished.

## Flight notes

- No controller mapping or game binding behavior changed in this release.
- The bridge still starts only with FPV SkyDive and begins with neutral Xbox controls.

## Verification

- All 13 Rust unit tests passed.
- PowerShell script checks passed.
- A Rust release build and virtual-Xbox self-test passed.
- Release artifacts will be privacy-scanned and SHA-256 verified by the local release script.

## Install or update

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.83/bootstrap.ps1 | iex
```
