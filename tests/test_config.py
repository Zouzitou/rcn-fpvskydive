from rcn_fpv.config import default_config, load_config, save_config

def test_config_roundtrip_and_safe_defaults(tmp_path):
    config = default_config(); config["transmitter_mode"] = "mode1"; save_config(tmp_path, config)
    assert load_config(tmp_path)["transmitter_mode"] == "mode1"
    (tmp_path / "state" / "config.json").write_text("not json")
    assert load_config(tmp_path)["transmitter_mode"] == "mode2"
