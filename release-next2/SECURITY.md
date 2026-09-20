# Security note

The installer stores application files, logs, state, and a managed Python environment below `%LOCALAPPDATA%\\RCN-FPVSkyDive`. Downloads must be release-pinned and SHA-256 verified. Driver packages must be source-pinned, signature/provider checked, and hardware-ID matched before elevation and `pnputil`.

Elevation is not required for ordinary per-user files. If elevation is required for driver-store changes, the installer explains the reason and stops if approval is not granted. Logs are structured and diagnostic exports redact usernames, absolute local paths, and unrelated device data.
