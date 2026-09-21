# FPV SkyDive integration

The installer configures FPV SkyDive's Steam launch option automatically, so the normal **Play** button starts the bridge and game together. If Steam is open, a short-lived one-shot setup worker waits for Steam to exit, then safely updates only its FPV SkyDive entry. No bridge runs while it waits, and no manual Launch Options copy/paste or installer rerun is required. Existing FPV SkyDive launch arguments are preserved and the uninstaller restores the original setting.

Steam supplies `%command%` as the normal game executable and arguments. The wrapper starts the native bridge and waits for its virtual Xbox target before starting the game. FPV SkyDive may hand off from Steam's initial process to its actual game process; the wrapper keeps the bridge alive across that handoff and stops the same bridge process only after the game has been absent for five seconds. The user flow is:

1. Confirm the virtual Xbox controller is present.
2. Open FPV SkyDive’s controller calibration screen.
3. Move one requested axis at a time.
4. Confirm the detected axis and direction.
5. Review the final mapping summary.
6. Leave Arm, Pause, Restart, and Recover bindings untouched unless the user explicitly assigns them.

No stable official import format is assumed until verified against the installed game build.
