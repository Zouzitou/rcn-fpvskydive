from rcn_fpv.steam import find_fpv_skydive, parse_library_paths

def test_steam_library_paths_and_game_detection(tmp_path):
    assert parse_library_paths('"path" "C:\\\\Steam"') == [__import__('pathlib').Path('C:\\Steam')]
    root = tmp_path / "lib"; (root / "steamapps").mkdir(parents=True)
    (root / "steamapps" / "appmanifest_123.acf").write_text('"name" "FPV.SkyDive"\n"installdir" "FPV SkyDive"')
    assert find_fpv_skydive([root])[0]["name"] == "FPV.SkyDive"
