def test_watchdog_module_is_importable():
    from rcn_fpv import watchdog
    assert callable(watchdog.run)
