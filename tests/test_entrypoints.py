from pathlib import Path
from rcn_fpv.config import load_config

def test_runtime_modules_have_main_guards():
    for name in ("cli.py", "service.py", "watchdog.py"):
        text = (Path(__file__).parents[1] / "src" / "rcn_fpv" / name).read_text()
        assert 'if __name__ == "__main__":' in text

def test_bootstrap_installs_uninstaller():
    bootstrap = (Path(__file__).parents[1] / "bootstrap.ps1").read_text()
    assert "uninstall.ps1" in bootstrap

from rcn_fpv import cli

def test_stop_command_creates_safe_request(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "ROOT", tmp_path)
    assert cli.main(["stop"]) == 0
    assert (tmp_path / "state" / "stop.request").exists()
    assert "stop requested" in capsys.readouterr().out

def test_config_command_updates_one_axis(tmp_path, monkeypatch):
    monkeypatch.setattr(cli, "ROOT", tmp_path)
    assert cli.main(["config", "--axis", "left_x", "--invert", "on", "--dead-zone", "0.1"]) == 0
    config = load_config(tmp_path)
    assert config["axes"]["left_x"]["invert"] is True and config["axes"]["left_x"]["dead_zone"] == 0.1

def test_repair_requires_complete_managed_install(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "ROOT", tmp_path)
    assert cli.main(["repair"]) == 2
    assert "managed files are incomplete" in capsys.readouterr().err
