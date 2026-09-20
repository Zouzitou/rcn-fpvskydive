def test_watchdog_module_is_importable():
    from rcn_fpv import watchdog
    assert callable(watchdog.run)

def test_watchdog_handles_service_spawn_failure(tmp_path, monkeypatch):
    from rcn_fpv import watchdog
    monkeypatch.setattr(watchdog.subprocess, "Popen", lambda *_: (_ for _ in ()).throw(OSError("spawn failed")))
    monkeypatch.setattr(watchdog.time, "sleep", lambda _: None)
    assert watchdog.run(tmp_path, max_restarts=1) == 1
