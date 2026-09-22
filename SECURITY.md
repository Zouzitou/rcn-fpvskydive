# Security note

The installer stores application files, logs, and state below `%LOCALAPPDATA%\\RCN-FPVSkyDive`. The published binary ZIP and the optional source-build ZIP are each release-pinned and SHA-256 verified before use. The native release has no Python runtime dependency. Driver packages must be explicitly supplied, carry a DJI provider declaration and matching hardware ID, and reference an in-package valid catalog signed by DJI or a trusted Microsoft hardware publisher before elevation and `pnputil`; `driver.ps1` rejects unsafe paths, unsigned catalogs, and non-DJI packages.

`install-from-source.ps1` is an opt-in transparency path. It downloads the release-pinned source ZIP matching its own tag, verifies its SHA-256 before extraction, requires an already installed local Rust toolchain, builds the bridge locally, scans the result for the local username and the project's former private identifier, prints the executable SHA-256, and retains the complete source tree under `%LOCALAPPDATA%\\RCN-FPVSkyDive\\source-cache` for inspection. It does not silently install Rust or a driver. The release workflow applies Rust path remapping, strips symbols, and rejects binary or ZIP artifacts that contain either private identifier.

The copy-paste command necessarily begins by downloading a bootstrap script. Its release ZIP is integrity-checked by a hash embedded in that bootstrap script, but the first download is not independently code-signed. For the strongest manual verification, download a versioned `bootstrap.ps1` and compare it with the matching release's published `SHA256SUMS.txt` before running it. Do not run a bootstrap script from an untrusted mirror.

Elevation is not required for ordinary per-user files. If elevation is required for driver-store changes, the installer explains the reason and stops if approval is not granted. Logs are structured and diagnostic exports redact usernames, absolute local paths, and unrelated device data.

To inspect an official VCOM package without changing Windows, run `driver.ps1 -Action validate -InfPath <path-to-inf>`. Only `-Action install` requests elevation and stages the package.
