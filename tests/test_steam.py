from rcn_fpv.steam import find_fpv_skydive, launch_fpv_skydive, parse_library_paths, steam_library_roots

def test_steam_library_paths_and_game_detection(tmp_path):
    assert parse_library_paths('"path" "C:\\\\Steam"') == [__import__('pathlib').Path('C:\\Steam')]
    root = tmp_path / "lib"; (root / "steamapps").mkdir(parents=True)
    (root / "steamapps" / "appmanifest_123.acf").write_text('"name" "FPV.SkyDive"\n"installdir" "FPV SkyDive"')
    game = find_fpv_skydive([root])[0]
    assert game["name"] == "FPV.SkyDive" and game["app_id"] == "123"
    opened = []
    assert launch_fpv_skydive([root], opened.append)["launch_uri"] == "steam://rungameid/123"
    assert opened == ["steam://rungameid/123"]

def test_steam_library_roots_include_configured_libraries(tmp_path):
    steam = tmp_path / "Steam"; library = tmp_path / "OtherLibrary"
    (steam / "steamapps").mkdir(parents=True)
    escaped = str(library).replace("\\", "\\\\")
    (steam / "steamapps" / "libraryfolders.vdf").write_text('"path" "' + escaped + '"')
    assert library in steam_library_roots([steam])
