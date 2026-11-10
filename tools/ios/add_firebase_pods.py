#!/usr/bin/env python3
"""Write a Podfile so the exported iOS app links Firebase Analytics and Crashlytics.

Godot copies the plist only. The pods supply the SDK. Static linkage keeps the
frameworks inside the app target Godot already signs.
"""

from __future__ import annotations

import sys
from pathlib import Path

PODFILE = """platform :ios, '15.0'
use_frameworks! :linkage => :static

target '{target}' do
  pod 'Firebase/Analytics', '11.6.0'
  pod 'Firebase/Crashlytics', '11.6.0'
end
"""


def write_podfile(export_root: Path) -> Path:
    projects = [p for p in export_root.rglob("*.xcodeproj") if "Pods" not in p.parts]
    if not projects:
        raise SystemExit(f"no xcodeproj under {export_root}")
    project = projects[0]
    target = project.stem
    dest = project.parent / "Podfile"
    dest.write_text(PODFILE.format(target=target), encoding="utf-8")
    print(f"Wrote {dest} for target {target}")
    return dest


def self_test() -> int:
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        proj = root / "SewLens.xcodeproj"
        proj.mkdir()
        path = write_podfile(root)
        text = path.read_text(encoding="utf-8")
        if "target 'SewLens'" not in text or "Firebase/Crashlytics" not in text:
            print("self-test failed", file=sys.stderr)
            return 1
        if write_podfile(root) != path:
            print("self-test rewrite failed", file=sys.stderr)
            return 1
    print("add_firebase_pods self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 2:
        print("usage: add_firebase_pods.py <export-root> | --self-test", file=sys.stderr)
        return 1
    write_podfile(Path(argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
