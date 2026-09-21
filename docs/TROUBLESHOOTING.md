# Troubleshooting matrix

| State | Meaning | Action |
|---|---|---|
| Controller not detected | No supported VID/PID/interface evidence | Power the controller, use a data cable, and inspect the USB-C port. |
| Debug interface only | `MI_04`/For Debug is present but no Protocol interface | Close DJI Assistant 2, reconnect, and allow Windows to rescan. |
| Missing VCOM driver | Ports-class driver is absent | Install the official DJI VCOM driver, reconnect the controller, then confirm that Windows exposes `DEVICE USB VCOM For Protocol`. |
| Protocol port busy | A process owns the selected COM port | Close DJI Assistant 2 and other serial tools, then retry. |
| Unsupported protocol | Device is recognized but no validated decoder exists | Export diagnostics; do not use the bridge as connected. |
| Virtual gamepad failed | ViGEmBus is unavailable | Install or repair Nefarius ViGEmBus, then rerun `rcn-bridge self-test`. |

RC-N2 and RC-N3 are intentionally reported as unsupported pending protocol implementation when their USB behavior does not match a validated decoder.
