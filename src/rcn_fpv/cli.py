import argparse, json, os, subprocess, sys
from pathlib import Path
from . import __version__
from .diagnostics import report
from .driver import DriverInstallError, install_managed_driver
from .discovery import choose_candidate, enumerate_protocol_ports
from .config import AXIS_NAMES, load_config, save_config
from .steam import launch_fpv_skydive, steam_library_roots

ROOT = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "RCN-FPVSkyDive"

def main(argv=None):
    p = argparse.ArgumentParser(prog="rcn-fpv", description="DJI RC-N bridge for FPV SkyDive")
    p.add_argument("command", choices=["status", "diagnose", "start", "stop", "repair", "uninstall", "config", "driver-install", "open-game"])
    p.add_argument("--inf", type=Path, help="Official DJI INF placed under the managed drivers folder")
    p.add_argument("--mode", choices=["mode1", "mode2"])
    p.add_argument("--axis", choices=AXIS_NAMES)
    p.add_argument("--invert", choices=["on", "off"])
    p.add_argument("--center", type=float)
    p.add_argument("--dead-zone", type=float)
    p.add_argument("--saturation", type=float)
    p.add_argument("--exponent", type=float)
    args = p.parse_args(argv)
    state = ROOT / "state" / "health.json"
    if args.command == "status":
        if state.exists(): print(state.read_text(encoding="utf-8"))
        else: print(json.dumps({"state": "not-installed", "version": __version__}))
        return 0
    if args.command == "diagnose":
        candidates = enumerate_protocol_ports()
        selected = choose_candidate(candidates)
        print(json.dumps(report(ROOT, {"version": __version__, "state_file": state.exists(),
            "usb_devices": [c.__dict__ for c in candidates],
            "protocol_port": selected.__dict__ if selected else None}), indent=2))
        return 0
    if args.command == "config":
        config = load_config(ROOT)
        changed = False
        if args.mode:
            config["transmitter_mode"] = args.mode; changed = True
        axis_values = {"invert": args.invert, "center": args.center, "dead_zone": args.dead_zone,
                       "saturation": args.saturation, "exponent": args.exponent}
        if any(value is not None for value in axis_values.values()):
            if not args.axis:
                print("config failed safely: --axis is required when changing an axis setting", file=sys.stderr)
                return 2
            target = config["axes"][args.axis]
            for name, value in axis_values.items():
                if value is not None:
                    target[name] = value == "on" if name == "invert" else value
                    changed = True
        if changed: save_config(ROOT, config)
        print(json.dumps(config, indent=2))
        return 0
    if args.command == "driver-install":
        try:
            evidence = install_managed_driver(ROOT, args.inf)
        except DriverInstallError as exc:
            print(f"driver installation failed safely: {exc}", file=sys.stderr)
            return 2
        print(json.dumps({"provider": evidence.provider, "version": evidence.version, "status": "verified installed"}))
        return 0
    if args.command == "open-game":
        try:
            print(json.dumps(launch_fpv_skydive(steam_library_roots())))
            return 0
        except (FileNotFoundError, OSError) as exc:
            print(f"open-game failed safely: {exc}", file=sys.stderr)
            return 2
    if args.command == "start":
        try:
            (ROOT / "state" / "stop.request").unlink(missing_ok=True)
            from .service import run
            run(ROOT)
            return 0
        except KeyboardInterrupt:
            return 0
        except Exception as exc:
            print(f"start failed safely: {exc}", file=sys.stderr)
            return 2
    if args.command == "stop":
        request = ROOT / "state" / "stop.request"
        request.parent.mkdir(parents=True, exist_ok=True)
        request.write_text("operator requested a safe bridge stop\n", encoding="utf-8")
        print("stop requested: the bridge will neutralize controls and exit safely")
        return 0
    if args.command == "repair":
        python = ROOT / ".venv" / "Scripts" / "python.exe"
        app = ROOT / "app"
        startup = ROOT / "startup.ps1"
        if not python.exists() or not app.exists() or not startup.exists():
            print("repair failed safely: managed files are incomplete; rerun the verified bootstrapper", file=sys.stderr)
            return 2
        package = subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                                  "--no-deps", "--no-build-isolation", str(app)], check=False)
        if package.returncode:
            print("repair failed safely: local package reinstall failed; rerun the verified bootstrapper", file=sys.stderr)
            return package.returncode
        startup_result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                         str(startup), "-Action", "install"], check=False)
        if startup_result.returncode:
            print("repair failed safely: startup registration failed", file=sys.stderr)
            return startup_result.returncode
        print("repair complete: managed package and startup registration restored")
        return 0
    if args.command == "uninstall":
        uninstall = ROOT / "uninstall.ps1"
        if not uninstall.exists():
            print("uninstall failed safely: managed uninstaller is missing; remove the release with its verified uninstall.ps1", file=sys.stderr)
            return 2
        escaped = str(uninstall).replace("'", "''")
        command = f"Start-Sleep -Seconds 1; & '{escaped}' -Confirm:$false"
        subprocess.Popen(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command])
        print("uninstall scheduled: startup registration and managed files will be removed after this command exits")
        return 0
    print(f"{args.command}: installer/runtime operation is not available until installed via bootstrap.ps1", file=sys.stderr)
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
