#!/usr/bin/env python3
"""UI integration fixture: use ONLY in a disposable app copy; never edits a deck."""
import importlib.util
import os
from pathlib import Path
import time
import subprocess
import sys

os.setpgid(0, 0)
spec = importlib.util.spec_from_file_location("real_staging", Path(__file__).with_name("stage-drawing-real.py"))
staging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(staging)
root = Path(os.environ["PPT_CURSOR_CONTROL_DIRECTORY"])
evidence = Path(os.environ["PPT_CURSOR_SHUTDOWN_EVIDENCE"]) / str(os.getpid())
evidence.mkdir(parents=True, mode=0o700)
(evidence / "control.txt").write_text(str(root))
with staging.preview_transaction() as active:
    if active:
        preview = os.environ.get("PPT_CURSOR_SHUTDOWN_PREVIEW")
        if preview:
            (evidence / "ready").touch()
            binary = Path(__file__).resolve().parents[1] / "MacOS/PPTCursor"
            subprocess.run([str(binary), "--show-staged-preview", preview], check=True)
            (evidence / "preview-closed").touch()
        else:
            print("PPT_CURSOR_PHASE=写入", flush=True)
            print("本地恢复测试：模拟慢写入，不修改 PowerPoint 文稿。", flush=True)
            (evidence / "ready").touch()
            while not (root / "stop").exists():
                time.sleep(.02)
            time.sleep(3)
            (evidence / "write-finished").touch()
            time.sleep(1)
            (evidence / "checkpoint-finished").touch()
print("本地恢复测试：写入与缓存阶段均已结束。", flush=True)
