from rcn_fpv.logging import JsonlLogger, tail

def test_jsonl_logging_and_tail(tmp_path):
    logger = JsonlLogger(tmp_path); logger.event("startup", port="COM7")
    assert '"event":"startup"' in tail(tmp_path)[0]
