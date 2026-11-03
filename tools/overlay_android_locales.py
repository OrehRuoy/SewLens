#!/usr/bin/env python3
"""Copy android/locale-res onto an installed Godot Android build template."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "android" / "locale-res"
DEST = ROOT / "android" / "build" / "res"


def main() -> int:
    if not SRC.is_dir():
        print(f"missing {SRC}", file=sys.stderr)
        return 1
    if not DEST.is_dir():
        print(f"missing {DEST}; install the Android build template first", file=sys.stderr)
        return 1
    for item in SRC.iterdir():
        target = DEST / item.name
        if not item.is_dir():
            shutil.copy2(item, target)
            continue
        target.mkdir(parents=True, exist_ok=True)
        for child in item.iterdir():
            shutil.copy2(child, target / child.name)
        strings = target / "strings.xml"
        old = target / "godot_project_name_string.xml"
        if strings.is_file() and old.is_file() and "godot_project_name_string" in strings.read_text(encoding="utf-8"):
            old.unlink()
    print(f"Overlaid {SRC} onto {DEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
