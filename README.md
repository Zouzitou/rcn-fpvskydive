# RCN FPV SkyDive

Use your **DJI RC-N1** as an Xbox controller in **FPV SkyDive** on Windows.

Plug in the controller, start the game, and fly. The bridge starts only with FPV SkyDive and disappears again when the game closes.

> **Supported today:** RC-N1, hardware-tested. RC-N2 and RC-N3 are detected safely but are not claimed as supported until their real USB stick protocol is tested.

## Before you start

You need a Windows 10/11 PC, FPV SkyDive installed through Steam, a powered-on RC-N1, and a data-capable USB-C cable. You do **not** need Python, a terminal setup, or administrator rights for the normal install.

## Get flying

### 1. Install

Open **PowerShell**, paste this, and wait for the orange “Installation Complete” screen:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.51/bootstrap.ps1 | iex
```

It is a fixed, SHA-256-verified release installer. It does not silently install a driver, change your game bindings, show your Windows username, or run the bridge at login.

### 2. Plug in your controller

Power on the RC-N1 and connect it with a proper USB data cable. If Windows shows a `DEVICE USB VCOM For Protocol` port, you are ready for the next step. The bridge deliberately ignores the Debug port.

### 3. Launch FPV SkyDive

Click **Start Menu → RCN FPV SkyDive**. It waits for the virtual Xbox controller, starts FPV SkyDive, and stops the bridge after you exit the game.

Want to launch straight from Steam instead? Add this once in **FPV SkyDive → Properties → General → Launch Options**:

```text
cmd.exe /d /c call "%LOCALAPPDATA%\RCN-FPVSkyDive\launch-fpv.cmd" %command%
```

### 4. Calibrate once in-game

In FPV SkyDive, open its controller/calibration settings and bind the four stick axes. The safe Mode 2 defaults are:

| RC-N1 stick | Flight control |
| --- | --- |
| Left stick up/down | Throttle |
| Left stick left/right | Yaw |
| Right stick up/down | Pitch |
| Right stick left/right | Roll |

The bridge does not invent Arm, Pause, Restart, or Recover bindings—choose those in the game if you want them.

## If something does not work

Open the Flight Console:

```powershell
& "$env:LOCALAPPDATA\RCN-FPVSkyDive\bin\rcn-bridge.exe" tui
```

It tells you whether the RC-N1, virtual Xbox controller, and FPV SkyDive are ready. Press `v` to verify stick movement and `l` to launch the game. If the controller is not found, see the [troubleshooting guide](docs/TROUBLESHOOTING.md).

If Windows has no Protocol port, you may need DJI’s official VCOM driver. The app never installs it behind your back. Follow the deliberate driver instructions in [the troubleshooting guide](docs/TROUBLESHOOTING.md).

## Safety and privacy

- The bridge outputs neutral sticks whenever it starts, disconnects, or stops.
- It runs only while FPV SkyDive is open—never at Windows login.
- The installer is per-user and verifies the published release hash before installing it.
- Your game bindings are never edited automatically.

## For developers and curious pilots

Want to inspect and compile the app yourself? Install stable Rust from [rustup.rs](https://rustup.rs), then run:

```powershell
irm https://raw.githubusercontent.com/Zouzitou/rcn-fpvskydive/v0.1.51/install-from-source.ps1 | iex
```

The same orange installer builds the tagged source locally and keeps its source/build log private on your machine. For architecture, acceptance evidence, and hardware test plans, see [ARCHITECTURE.md](ARCHITECTURE.md), [ACCEPTANCE.md](ACCEPTANCE.md), and [docs/HARDWARE_IN_LOOP.md](docs/HARDWARE_IN_LOOP.md).

To work on the Rust bridge:

```powershell
cargo test --manifest-path rust-bridge/Cargo.toml
cargo build --release --manifest-path rust-bridge/Cargo.toml
```
