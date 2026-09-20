from pathlib import Path

def test_runtime_modules_have_main_guards():
    for name in ("cli.py", "service.py", "watchdog.py"):
        text = (Path(__file__).parents[1] / "src" / "rcn_fpv" / name).read_text()
        assert 'if __name__ == "__main__":' in text
