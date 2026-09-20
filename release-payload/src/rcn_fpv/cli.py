import argparse, json, os, sys
from pathlib import Path
from . import __version__
from .diagnostics import report
from .discovery import choose_candidate, enumerate_protocol_ports

ROOT = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "RCN-FPVSkyDive"

def main(argv=None):
    p = argparse.ArgumentParser(prog="rcn-fpv", description="DJI RC-N bridge for FPV SkyDive")
    p.add_argument("command", choices=["status", "diagnose", "start", "stop", "repair", "uninstall"])
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
            "usb_candidates": [c.__dict__ for c in candidates],
            "selected_protocol_port": selected.__dict__ if selected else None}), indent=2))
        return 0
    if args.command == "start":
        try:
            from .service import run
            run(ROOT)
            return 0
        except KeyboardInterrupt:
            return 0
        except Exception as exc:
            print(f"start failed safely: {exc}", file=sys.stderr)
            return 2
    if args.command == "stop":
        print("stop: request the running bridge to stop from its console or service manager")
        return 0
    if args.command == "repair":
        print("repair: rerun the verified bootstrapper to repair the managed environment")
        return 0
    if args.command == "uninstall":
        print("uninstall: run uninstall.ps1 from the verified release")
        return 0
    print(f"{args.command}: installer/runtime operation is not available until installed via bootstrap.ps1", file=sys.stderr)
    return 2
