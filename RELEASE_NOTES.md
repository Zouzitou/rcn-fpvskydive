# RCN FPV SkyDive v0.1.84

## Highlights

- Uninstall now restores FPV SkyDive's normal Steam launch setting before removing the bridge.
- Recovery handles an interrupted uninstall even when the bridge folder or saved installer state is already missing.
- Steam is closed cleanly before its per-game launch configuration is changed.

## Flight notes

- No controller mapping or game binding behavior changed in this release.
- The bridge still starts only with FPV SkyDive and begins with neutral Xbox controls.

## Verification

- PowerShell script checks passed.
- Release artifacts will be privacy-scanned and SHA-256 verified by the local release script.

## Install or update

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.84/bootstrap.ps1 | iex
```
