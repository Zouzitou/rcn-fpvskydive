# Security note

The installer stores application files, logs, and state below `%LOCALAPPDATA%\\RCN-FPVSkyDive`. Downloads are release-pinned and SHA-256 verified. The native release has no Python runtime dependency. Driver packages must be explicitly supplied, carry a DJI provider declaration and matching hardware ID, and reference an in-package valid catalog signed by DJI or a trusted Microsoft hardware publisher before elevation and `pnputil`; `driver.ps1` rejects unsafe paths, unsigned catalogs, and non-DJI packages.

`install-from-source.ps1` is an opt-in transparency path. It downloads a public tagged source archive, requires an already installed local Rust toolchain, builds the bridge locally, prints the executable SHA-256, and retains the complete source tree under `%LOCALAPPDATA%\\RCN-FPVSkyDive\\source-cache` for inspection. It does not silently install Rust or a driver. The normal bootstrapper remains the stronger integrity path for a published binary because it verifies a release-pinned archive hash before installation.

Elevation is not required for ordinary per-user files. If elevation is required for driver-store changes, the installer explains the reason and stops if approval is not granted. Logs are structured and diagnostic exports redact usernames, absolute local paths, and unrelated device data.

To inspect an official VCOM package without changing Windows, run `driver.ps1 -Action validate -InfPath <path-to-inf>`. Only `-Action install` requests elevation and stages the package.
