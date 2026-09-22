# RCN FPV SkyDive v0.1.81

## Highlights

- The Flight Console now enables stick verification whenever FPV SkyDive is closed, even if an old status file still says the bridge is connected.
- Stick verification automatically clears a leftover game bridge session before opening the controller port.
- The installer now hides the raw JSON verification report and shows a concise four-direction result instead.
- Updated the stick-check wording to tell pilots to close FPV SkyDive, not to close the bridge.

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
