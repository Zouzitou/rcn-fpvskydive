from rcn_fpv.config import axis_configs, default_config, load_config, save_config

def test_config_roundtrip_and_safe_defaults(tmp_path):
    config = default_config(); config["transmitter_mode"] = "mode1"; save_config(tmp_path, config)
    assert load_config(tmp_path)["transmitter_mode"] == "mode1"
    (tmp_path / "state" / "config.json").write_text("not json")
    assert load_config(tmp_path)["transmitter_mode"] == "mode2"

def test_axis_configs_merge_partial_values_and_clamp_unsafe_values():
    config = {"axes": {"left_x": {"invert": True, "dead_zone": 9, "saturation": 0, "exponent": -1}}}
    axes = axis_configs(config)
    assert axes["left_x"].invert and axes["left_x"].dead_zone == 0.99
    assert axes["left_x"].saturation > 0 and axes["left_x"].exponent > 0
    assert axes["right_y"].dead_zone == 0.03
