# RCN FPV SkyDive v0.1.80

## Highlights

- Made the virtual Xbox self-test retry a temporary Windows readiness delay across its entire test cycle. This prevents a false failure when ViGEm accepts the controller briefly after its first status response.

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
