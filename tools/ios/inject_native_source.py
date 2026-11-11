#!/usr/bin/env python3
"""Copy the iOS bridge into a Godot-exported Xcode project and compile it.

SewLensNative.m and SewLensStore.swift go to <export>/SewLens/. The pbxproj
reference uses SOURCE_ROOT so CocoaPods' Pods group cannot claim the path.
The Swift file links StoreKit. Pattern from Circuit Sort's inject_share_source.py.
"""

from __future__ import annotations

import re
import shutil
import sys
import tempfile
from pathlib import Path

FILE_REF_ID = "5E1E05000000000000000001"
BUILD_FILE_ID = "5E1E05000000000000000002"
SWIFT_REF_ID = "5E1E05000000000000000003"
SWIFT_BUILD_ID = "5E1E05000000000000000004"
FIREBASE_REF_ID = "5E1E05000000000000000005"
FIREBASE_BUILD_ID = "5E1E05000000000000000006"
SOURCE_NAME = "SewLensNative.m"
SWIFT_NAME = "SewLensStore.swift"
FIREBASE_NAME = "SewLensFirebase.m"
APP_GROUP = "SewLens"
RELATIVE_PATH = f"{APP_GROUP}/{SOURCE_NAME}"
SWIFT_PATH = f"{APP_GROUP}/{SWIFT_NAME}"
FIREBASE_PATH = f"{APP_GROUP}/{FIREBASE_NAME}"
REPO = Path(__file__).resolve().parents[2]
SOURCES = (
    (SOURCE_NAME, "sourcecode.c.objc", FILE_REF_ID, BUILD_FILE_ID, RELATIVE_PATH),
    (SWIFT_NAME, "sourcecode.swift", SWIFT_REF_ID, SWIFT_BUILD_ID, SWIFT_PATH),
    (FIREBASE_NAME, "sourcecode.c.objc", FIREBASE_REF_ID, FIREBASE_BUILD_ID, FIREBASE_PATH),
)


def _file_ref_line(name: str, file_type: str, ref_id: str, relative: str) -> str:
    return (
        f"\t\t{ref_id} /* {name} */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = {file_type}; "
        f"name = {name}; path = {relative}; sourceTree = SOURCE_ROOT; }};\n"
    )


def _build_file_line(name: str, ref_id: str, build_id: str) -> str:
    return (
        f"\t\t{build_id} /* {name} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {ref_id} /* {name} */; }};\n"
    )


def _add_source(text: str, name: str, file_type: str, ref_id: str, build_id: str, relative: str) -> str:
    ref_re = re.compile(
        rf"\t\t{ref_id} /\* {re.escape(name)} \*/ = \{{isa = PBXFileReference;[^}}]*\}};\n"
    )
    line = _file_ref_line(name, file_type, ref_id, relative)
    if ref_re.search(text):
        text = ref_re.sub(line, text, count=1)
    else:
        marker = "/* Begin PBXFileReference section */\n"
        if marker not in text:
            raise SystemExit("PBXFileReference section missing")
        text = text.replace(marker, marker + line, 1)

    if f"{build_id} /* {name} in Sources */ = " not in text:
        marker = "/* Begin PBXBuildFile section */\n"
        if marker not in text:
            raise SystemExit("PBXBuildFile section missing")
        text = text.replace(marker, marker + _build_file_line(name, ref_id, build_id), 1)

    groups_at = text.find("/* Begin PBXGroup section */")
    if groups_at == -1:
        raise SystemExit("PBXGroup section missing")
    if f"{ref_id} /* {name} */," not in text[groups_at:]:
        child = f"\t\t\t\t{ref_id} /* {name} */,\n"
        group = re.search(
            rf"(\t\t[A-Fa-f0-9]{{24}} /\* {APP_GROUP} \*/ = \{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)",
            text,
        )
        if group:
            text = text.replace(group.group(1), group.group(1) + child, 1)
        else:
            idx = groups_at
            while True:
                idx = text.find("children = (\n", idx)
                if idx == -1:
                    raise SystemExit("no PBXGroup outside Pods and Products")
                window = text[idx : idx + 800]
                if any(f"{kind} = {name};" in window for kind in ("path", "name") for name in ("Pods", "Products")):
                    idx += 13
                    continue
                at = idx + len("children = (\n")
                text = text[:at] + child + text[at:]
                break

    item = f"{build_id} /* {name} in Sources */,"
    if item not in text:
        phase = text.find("isa = PBXSourcesBuildPhase;")
        if phase == -1:
            raise SystemExit("PBXSourcesBuildPhase missing")
        files = text.find("files = (", phase)
        if files == -1:
            raise SystemExit("Sources files list missing")
        at = files + len("files = (")
        text = text[:at] + f"\n\t\t\t\t{item}" + text[at:]
    return text


def _ensure_swift_settings(text: str) -> str:
    marker = "buildSettings = {\n"
    start = 0
    while True:
        at = text.find(marker, start)
        if at == -1:
            return text
        end = text.find("\n\t\t\t};", at)
        if end == -1:
            return text
        block = text[at:end]
        if "com.sewlens.app" in block:
            extra = ""
            if "SWIFT_VERSION" not in block:
                extra += "\t\t\t\tSWIFT_VERSION = 5.0;\n"
            if "StoreKit" not in block:
                extra += '\t\t\t\tOTHER_LDFLAGS = ("$(inherited)", "-framework", "StoreKit");\n'
            if extra:
                text = text[: at + len(marker)] + extra + text[at + len(marker) :]
                end = text.find("\n\t\t\t};", at)
        start = end + 1


def inject_text(text: str) -> str:
    for name, file_type, ref_id, build_id, relative in SOURCES:
        text = _add_source(text, name, file_type, ref_id, build_id, relative)
    return _ensure_swift_settings(text)


def inject_tree(export_root: Path) -> int:
    for name, _file_type, _ref_id, _build_id, relative in SOURCES:
        src = REPO / "ios" / "native" / name
        if not src.is_file():
            raise SystemExit(f"missing {src}")
        dest = export_root / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
    changed = 0
    projects = [p for p in export_root.rglob("project.pbxproj") if "Pods" not in p.parts]
    if not projects:
        raise SystemExit(f"no project.pbxproj under {export_root}")
    for pbx in projects:
        original = pbx.read_text(encoding="utf-8")
        updated = inject_text(original)
        if updated != original:
            pbx.write_text(updated, encoding="utf-8")
            changed += 1
            print(f"Injected native sources into {pbx}")
        else:
            print(f"native sources already in {pbx}")
    return changed


FIXTURE = (
    "/* Begin PBXBuildFile section */\n"
    "\t\tAAAAAAAAAAAAAAAAAAAAAAA1 /* main.m in Sources */ = {isa = PBXBuildFile; fileRef = AAAAAAAAAAAAAAAAAAAAAAA2 /* main.m */; };\n"
    "/* End PBXBuildFile section */\n"
    "/* Begin PBXFileReference section */\n"
    "\t\tAAAAAAAAAAAAAAAAAAAAAAA2 /* main.m */ = {isa = PBXFileReference; path = main.m; sourceTree = \"<group>\"; };\n"
    "/* End PBXFileReference section */\n"
    "/* Begin PBXGroup section */\n"
    "\t\tBBBBBBBBBBBBBBBBBBBBBBB1 /* Pods */ = {\n"
    "\t\t\tisa = PBXGroup;\n"
    "\t\t\tchildren = (\n"
    "\t\t\t);\n"
    "\t\t\tname = Pods;\n"
    "\t\t};\n"
    "\t\tBBBBBBBBBBBBBBBBBBBBBBB2 /* SewLens */ = {\n"
    "\t\t\tisa = PBXGroup;\n"
    "\t\t\tchildren = (\n"
    "\t\t\t\tAAAAAAAAAAAAAAAAAAAAAAA2 /* main.m */,\n"
    "\t\t\t);\n"
    "\t\t\tpath = SewLens;\n"
    "\t\t};\n"
    "/* End PBXGroup section */\n"
    "/* Begin PBXSourcesBuildPhase section */\n"
    "\t\tCCCCCCCCCCCCCCCCCCCCCCC1 /* Sources */ = {\n"
    "\t\t\tisa = PBXSourcesBuildPhase;\n"
    "\t\t\tbuildActionMask = 2147483647;\n"
    "\t\t\tfiles = (\n"
    "\t\t\t\tAAAAAAAAAAAAAAAAAAAAAAA1 /* main.m in Sources */,\n"
    "\t\t\t);\n"
    "\t\t};\n"
    "/* End PBXSourcesBuildPhase section */\n"
    "/* Begin XCBuildConfiguration section */\n"
    "\t\tDDDDDDDDDDDDDDDDDDDDDDD1 /* Debug */ = {\n"
    "\t\t\tisa = XCBuildConfiguration;\n"
    "\t\t\tbuildSettings = {\n"
    "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.sewlens.app;\n"
    "\t\t\t};\n"
    "\t\t\tname = Debug;\n"
    "\t\t};\n"
    "/* End XCBuildConfiguration section */\n"
)


def self_test() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        proj = root / "SewLens.xcodeproj"
        proj.mkdir()
        pbx = proj / "project.pbxproj"
        pbx.write_text(FIXTURE, encoding="utf-8")
        if inject_tree(root) != 1:
            print("first inject did not change the project", file=sys.stderr)
            return 1
        text = pbx.read_text(encoding="utf-8")
        checks = {
            "file copied": (root / RELATIVE_PATH).is_file(),
            "SOURCE_ROOT reference": f"path = {RELATIVE_PATH}; sourceTree = SOURCE_ROOT;" in text,
            "in app group": text.find(f"{FILE_REF_ID} /* {SOURCE_NAME} */,") > text.find("/* SewLens */ = {"),
            "not in Pods group": text.find(f"{FILE_REF_ID} /* {SOURCE_NAME} */,") > text.find("name = Pods;"),
            "in Sources phase": f"{BUILD_FILE_ID} /* {SOURCE_NAME} in Sources */," in text,
            "swift copied": (root / SWIFT_PATH).is_file(),
            "swift reference": f"path = {SWIFT_PATH}; sourceTree = SOURCE_ROOT;" in text,
            "swift in Sources": f"{SWIFT_BUILD_ID} /* {SWIFT_NAME} in Sources */," in text,
            "store boot is called": "sewlens_store_boot();" in (root / RELATIVE_PATH).read_text(encoding="utf-8"),
            "store poll is called": "sewlens_store_poll();" in (root / RELATIVE_PATH).read_text(encoding="utf-8"),
            "swift exports boot": '@_cdecl("sewlens_store_boot")' in (root / SWIFT_PATH).read_text(encoding="utf-8"),
            "swift keeps the product task": "private static var active: Task<Void, Never>?" in (root / SWIFT_PATH).read_text(encoding="utf-8"),
            "StoreKit linked": '-framework", "StoreKit"' in text,
            "swift version": "SWIFT_VERSION = 5.0;" in text,
            "firebase copied": (root / FIREBASE_PATH).is_file(),
            "firebase in Sources": f"{FIREBASE_BUILD_ID} /* {FIREBASE_NAME} in Sources */," in text,
        }
        for label, ok in checks.items():
            if not ok:
                print(f"self-test failed: {label}", file=sys.stderr)
                return 1
        if inject_tree(root) != 0 or pbx.read_text(encoding="utf-8") != text:
            print("second inject changed the project", file=sys.stderr)
            return 1
    print("inject_native_source self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 2:
        print("usage: inject_native_source.py <export-root> | --self-test", file=sys.stderr)
        return 1
    inject_tree(Path(argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
