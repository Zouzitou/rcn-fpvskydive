# Security note

The installer stores application files, logs, and state below `%LOCALAPPDATA%\\RCN-FPVSkyDive`. Downloads are release-pinned and SHA-256 verified. The native release has no Python runtime dependency. Driver packages must be explicitly supplied, authenticode-valid, and hardware-ID matched before elevation and `pnputil`; `driver.ps1` rejects unsigned or non-DJI INFs.

Elevation is not required for ordinary per-user files. If elevation is required for driver-store changes, the installer explains the reason and stops if approval is not granted. Logs are structured and diagnostic exports redact usernames, absolute local paths, and unrelated device data.
