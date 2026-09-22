# Installer evidence

This file records checks performed against the shipped payload rather than only the source tree.

## v0.1.28 on Windows 11

- Bootstrap source: `v0.1.28/bootstrap.ps1`
- Installation root: `%LOCALAPPDATA%\RCN-FPVSkyDive`
- Runtime: native Rust `rcn-bridge.exe` 0.1.28
- Login startup: disabled; `state/startup.json` reports `steam-launch-wrapper`
- Mapping file: created at `state/mapping.conf`
- ViGEm self-test: passed; neutral cleanup update sent
- Diagnostics: Protocol interface `DEVICE USB VCOM For Protocol (COM12)` selected; Debug COM11 also present and not selected; 13 valid live frames observed
- Lifecycle: native `start` followed by `stop` returned success and left no watcher process
- Wrapper lifecycle: `launch-fpv.ps1 cmd.exe /d /c exit 0` returned exit code 0, wrote `state/bridge.json` as `stopped`, and left zero watcher processes

The wrapper check uses a harmless local process as a stand-in for Steam because Steam/FPV SkyDive is not installed on that validation host.

## v0.1.39 RC-N1 + FPV SkyDive process-lifetime check on Windows 11

- Bootstrap source: `v0.1.39/bootstrap.ps1`; it completed with no startup-at-login registration.
- RC-N1 Protocol interface: `COM12`; the persisted four-axis verification covers the observed `364..1684` range for yaw, throttle, roll, and pitch.
- FPV SkyDive was started through `launch-fpv.ps1` only after the bridge reported `connected`.
- During the real FPV SkyDive game process, `rcn-bridge status` reported `connected`, `mapped_frames: 2478`, and the Windows PnP inventory reported `OK Xbox 360 Controller for Windows` (`XnaComposite`).
- This run caught and fixed the game launcher handoff: the wrapper now keeps the bridge alive through the short gap between the initial Steam process and FPV SkyDive's actual game process. It also retries transient ViGEm target readiness during installation and runtime startup.

This proves the released bridge remains present while the actual FPV SkyDive process is running. It does **not** prove FPV SkyDive's own input selector, axis calibration, or in-flight handling: the in-game controls inspection was stopped before that screen could be checked.

## RC-N1 + FPV SkyDive in-game controller detection on Windows 11

- Fresh native diagnostic found the powered RC-N1 Protocol interface at `COM12`, rejected the companion Debug interface at `COM11`, read 13 valid live frames, and confirmed the signed VCOM driver.
- During a live FPV SkyDive session, `game-check.ps1` observed the game process, a connected bridge with increasing mapped frames, and Windows' `Xbox 360 Controller for Windows` device.
- FPV SkyDive's **Settings → Controls** screen changed from **Keyboard And Mouse** to **XInput Gamepad 1** as soon as the bridge connected. It showed **Gamepad** input and the expected four assigned axes: Left Stick Y, Left Stick X, Right Stick Y, and Right Stick X.
- The in-game **Input Calibration → Configure** control was visible, but it was intentionally not opened and no game bindings were saved or changed during this inspection.
- Steam's launch-option setup was still queued because Steam had remained open since installation. The bridge for this evidence run was started manually; therefore a physical normal-Steam-Play launch/exit with the configured wrapper remains a separate gate.
- During a later v0.1.69 gameplay session, the user unplugged and reconnected the RC-N controller while FPV SkyDive remained open and confirmed control returned without restarting the game.

## Not yet proven

- RC-N2 and RC-N3 hardware and firmware behavior
- Clean-machine driver installation with an official DJI INF
- Sleep/resume and COM-renumbering behavior on separate hardware runs
- FPV SkyDive calibration and in-flight handling
