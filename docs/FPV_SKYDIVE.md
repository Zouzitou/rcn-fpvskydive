# FPV SkyDive integration

The bridge is launched by Steam only for FPV SkyDive. In the game's Steam **Properties → General → Launch Options**, add:

```text
cmd.exe /d /c ""%LOCALAPPDATA%\RCN-FPVSkyDive\launch-fpv.cmd" %command%"
```

Steam supplies `%command%` as the normal game executable and arguments. The wrapper starts the native bridge, waits for that game process to exit, and stops the same bridge process. The user flow is:

1. Confirm the virtual Xbox controller is present.
2. Open FPV SkyDive’s controller calibration screen.
3. Move one requested axis at a time.
4. Confirm the detected axis and direction.
5. Review the final mapping summary.
6. Leave Arm, Pause, Restart, and Recover bindings untouched unless the user explicitly assigns them.

No stable official import format is assumed until verified against the installed game build.
