import re
from pathlib import Path

def parse_library_paths(vdf_text: str):
    return [Path(p.replace('\\\\', '\\')) for p in re.findall(r'"path"\s+"([^"]+)"', vdf_text, re.I)]

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
