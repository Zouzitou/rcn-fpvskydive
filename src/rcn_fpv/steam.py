import re
import os
from pathlib import Path

def parse_library_paths(vdf_text: str):
    return [Path(p.replace('\\\\', '\\')) for p in re.findall(r'"path"\s+"([^"]+)"', vdf_text, re.I)]

def steam_library_roots(steam_roots=None):
    if steam_roots is None:
        steam_roots = [
            Path(value) / "Steam"
            for value in (os.environ.get("ProgramFiles(x86)"), os.environ.get("ProgramFiles"))
            if value
        ]
    roots = {Path(root) for root in steam_roots}
    for steam_root in tuple(roots):
        library_file = steam_root / "steamapps" / "libraryfolders.vdf"
        try: roots.update(parse_library_paths(library_file.read_text(encoding="utf-8", errors="replace")))
        except OSError: continue
    return sorted(roots, key=lambda path: str(path).lower())

def installed_games(library_root: Path):
    manifest_dir = library_root / "steamapps"
    games = []
    for manifest in manifest_dir.glob("appmanifest_*.acf"):
        try: text = manifest.read_text(encoding="utf-8", errors="replace")
        except OSError: continue
        name = re.search(r'"name"\s+"([^"]+)"', text, re.I)
        install = re.search(r'"installdir"\s+"([^"]+)"', text, re.I)
        app_id = re.search(r"appmanifest_(\d+)\.acf$", manifest.name, re.I)
        if name and install and app_id:
            games.append({"name": name.group(1), "app_id": app_id.group(1),
                          "path": str(manifest_dir / "common" / install.group(1))})
    return games

def find_fpv_skydive(library_roots, name="FPV.SkyDive"):
    matches = []
    for root in library_roots:
        for game in installed_games(Path(root)):
            if name.lower().replace(" ", "") in game["name"].lower().replace(" ", ""):
                matches.append(game)
    return matches

def launch_fpv_skydive(library_roots, opener=None):
    """Open the installed game through Steam only after an explicit CLI request."""
    games = find_fpv_skydive(library_roots)
    if not games:
        raise FileNotFoundError("FPV SkyDive was not found in the configured Steam libraries")
    game = sorted(games, key=lambda item: (item["name"].lower(), item["path"].lower()))[0]
    uri = "steam://rungameid/" + game["app_id"]
    (opener or os.startfile)(uri)
    return {"name": game["name"], "app_id": game["app_id"], "launch_uri": uri}
