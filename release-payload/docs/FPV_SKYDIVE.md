# FPV SkyDive integration

The bridge searches Steam library roots and app manifests; it does not assume `C:` or modify registry data. If the game is found, the user flow is:

1. Confirm the virtual Xbox controller is present.
2. Open FPV SkyDive’s controller calibration screen.
3. Move one requested axis at a time.
4. Confirm the detected axis and direction.
5. Review the final mapping summary.
6. Leave Arm, Pause, Restart, and Recover bindings untouched unless the user explicitly assigns them.

No stable official import format is assumed until verified against the installed game build.
