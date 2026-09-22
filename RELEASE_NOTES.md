# RCN FPV SkyDive v0.1.85

## Highlights

- Steam launches now use the full Windows command-processor path, preventing the "missing executable" error after installation.
- Repair and reinstall now replace an older broken Steam wrapper instead of incorrectly treating it as valid.
- Uninstall now clearly confirms that FPV SkyDive game files and saved settings were kept.

## Flight notes

- No controller mapping or game binding behavior changed in this release.
- The bridge still starts only with FPV SkyDive and begins with neutral Xbox controls.

## Verification

- PowerShell script checks passed, including a regression gate for the Steam executable path.
- FPV SkyDive and the RCN bridge were launched together successfully through Steam with the corrected wrapper.
- Release artifacts will be privacy-scanned and SHA-256 verified by the local release script.

## Install or update

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.85/bootstrap.ps1 | iex
```
