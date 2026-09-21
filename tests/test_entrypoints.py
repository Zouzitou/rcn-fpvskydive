from pathlib import Path
from rcn_fpv.config import load_config

def test_runtime_modules_have_main_guards():
    for name in ("cli.py", "service.py", "watchdog.py"):
        text = (Path(__file__).parents[1] / "src" / "rcn_fpv" / name).read_text()
        assert 'if __name__ == "__main__":' in text

def test_bootstrap_installs_uninstaller():
    bootstrap = (Path(__file__).parents[1] / "bootstrap.ps1").read_text()
    assert "uninstall.ps1" in bootstrap

def test_startup_records_an_immediate_launch_test():
    startup = (Path(__file__).parents[1] / "startup.ps1").read_text()
    assert "Test-BridgeLaunch" in startup and "startup_test=$launch" in startup

def test_release_uses_a_deterministic_allowlisted_archive():
    release = (Path(__file__).parents[1] / "release.ps1").read_text()
    assert "New-DeterministicZip" in release and "Sort-Object FullName" in release

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

def test_uninstall_schedules_managed_uninstaller(tmp_path, monkeypatch, capsys):
    (tmp_path / "uninstall.ps1").write_text("")
    calls = []
    monkeypatch.setattr(cli, "ROOT", tmp_path)
    monkeypatch.setattr(cli.subprocess, "Popen", lambda command: calls.append(command))
    assert cli.main(["uninstall"]) == 0
    assert calls and calls[0][0] == "powershell.exe"
    assert "uninstall scheduled" in capsys.readouterr().out

def test_driver_install_requires_a_managed_inf(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "ROOT", tmp_path)
    assert cli.main(["driver-install"]) == 2
    assert "managed drivers folder" in capsys.readouterr().err

def test_calibrate_reports_the_next_unverified_live_axis(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "ROOT", tmp_path)
    state = tmp_path / "state"; state.mkdir()
    (state / "health.json").write_text('{"state":"verifying_live_input","live_axes":["left_x"]}', encoding="utf-8")
    assert cli.main(["calibrate"]) == 0
    assert "left stick vertically" in capsys.readouterr().out

def test_status_does_not_claim_ready_without_every_evidence_gate(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "ROOT", tmp_path)
    state = tmp_path / "state"; state.mkdir()
    (state / "health.json").write_text('{"state":"connected","pid":999,"serial_open":true,"live_input_verified":true,"stability_verified":true,"virtual_gamepad_test":"virtual Xbox controller created, updated, and released"}', encoding="utf-8")
    monkeypatch.setattr(cli, "process_alive", lambda _: False)
    assert cli.main(["status"]) == 0
    assert '"ready": false' in capsys.readouterr().out
