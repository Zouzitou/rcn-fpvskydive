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
        if name and install: games.append({"name": name.group(1), "path": str(manifest_dir / "common" / install.group(1))})
    return games

def find_fpv_skydive(library_roots, name="FPV.SkyDive"):
    matches = []
    for root in library_roots:
        for game in installed_games(Path(root)):
            if name.lower().replace(" ", "") in game["name"].lower().replace(" ", ""):
                matches.append(game)
    return matches
