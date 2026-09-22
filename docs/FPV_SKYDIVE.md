# FPV SkyDive integration

The installer configures FPV SkyDive's Steam launch option automatically, so the normal **Play** button starts the bridge and game together. If Steam is open, a short-lived one-shot setup worker waits for Steam to exit, then safely updates only its FPV SkyDive entry. While it is waiting, it starts the bridge only if FPV SkyDive opens and stops the bridge again after the game closes. No manual Launch Options copy/paste or installer rerun is required. Existing FPV SkyDive launch arguments are preserved and the uninstaller restores the original setting.

Steam supplies `%command%` as the normal game executable and arguments. The wrapper starts the native bridge and then starts the game immediately; the bridge can remain waiting safely when the controller is powered off and will create the virtual Xbox target only after live input is verified. FPV SkyDive may hand off from Steam's initial process to its actual game process; the wrapper keeps the bridge alive across that handoff and stops the same bridge process only after the game has been absent for five seconds. The user flow is:

1. Start FPV SkyDive; the game can open with the controller powered off.
2. Power on and connect the RC-N controller while the game is running.
3. Wait for the virtual Xbox controller to appear, then open FPV SkyDive’s controller calibration screen.
4. Move one requested axis at a time.
5. Confirm the detected axis and direction.
6. Review the final mapping summary.
7. Leave Arm, Pause, Restart, and Recover bindings untouched unless the user explicitly assigns them.

No stable official import format is assumed until verified against the installed game build.
