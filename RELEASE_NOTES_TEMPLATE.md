# RCN FPV SkyDive v<version>

## Highlights

- <Describe the pilot-visible improvements in plain language.>

## Flight notes

- <State controller support honestly, including any known limitation or required one-time setup.>

## Verification

- <List the tests, hardware checks, or release-hash verification actually completed.>

## Install or update

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v<version>/bootstrap.ps1 | iex
```

## Maintainer instructions

Before every release, copy this file to `RELEASE_NOTES.md`, replace every placeholder, and make the heading match the exact tag. `release.ps1` refuses to publish missing, blank, placeholder-filled, or wrongly versioned notes. Keep the writing pilot-first: explain what changed, whether it affects flying, and exactly what was verified.
