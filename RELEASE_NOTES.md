# RCN FPV SkyDive v0.1.79

## Highlights

- Fixed Flight Console navigation: arrow keys and j/k now respond immediately while game and virtual-controller checks happen in the background.
- Fixed the guided stick-check return screen. It now returns to the Flight Console after any key, whether the check passes or reports a problem.
- Source builds now use the same five-step pilot setup flow as the normal installer, including Steam Play setup, controller detection, practical connection tips, and the optional four-stick check.

## Flight notes

- No controller mapping or game binding behavior changed in this release.
- The bridge still starts only with FPV SkyDive and begins with neutral Xbox controls.

## Verification

- PowerShell script parsing and the Windows PowerShell installer-banner regression check passed.
- All 13 Rust unit tests passed.
- A Rust release build passed.
- The published binary and source ZIPs will be SHA-256 verified after publication.

## Install or update

```powershell
irm https://github.com/Zouzitou/rcn-fpvskydive/releases/latest/download/bootstrap.ps1 | iex
```
