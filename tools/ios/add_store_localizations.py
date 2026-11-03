#!/usr/bin/env python3
"""Copy ios/InfoPlist/*.lproj into a Godot iOS export and register them.

Godot writes en.lproj only. App Store Connect lists a language when the .app
contains that .lproj and Info.plist CFBundleLocalizations names it. Run this
on the exported Xcode project before archive.
"""

from __future__ import annotations

import plistlib
import re
import sys
import tempfile
from pathlib import Path


LOCALES = ("en", "de", "fr", "es", "pt-BR", "ja", "it", "nl")
# Godot 4.6 names the Brazilian folder pt_BR.lproj. Apple also accepts pt-BR.
FOLDER_NAMES = {
    "pt-BR": ("pt-BR", "pt_BR"),
}
FILE_IDS = {
    "de": "A11CE5E10000000000000001",
    "fr": "A11CE5E10000000000000002",
    "es": "A11CE5E10000000000000003",
    "pt-BR": "A11CE5E10000000000000004",
    "ja": "A11CE5E10000000000000005",
    "it": "A11CE5E10000000000000006",
    "nl": "A11CE5E10000000000000007",
}
REPO = Path(__file__).resolve().parents[2]
LPROJ_SRC = REPO / "ios" / "InfoPlist"


def _quoted(lang: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_]+", lang):
        return lang
    return f'"{lang}"'


def _file_ref_id(text: str, lang: str) -> str:
    match = re.search(
        rf'([A-F0-9]{{24}}) /\* {re.escape(lang)} \*/ = \{{isa = PBXFileReference;'
        rf'[^}}]*path = "?{re.escape(lang)}\.lproj/InfoPlist\.strings"?;',
        text,
    )
    return match.group(1) if match else ""


def _insert_after(text: str, pattern: str, addition: str) -> str:
    match = re.search(pattern, text, re.M)
    if not match:
        raise SystemExit(f"pbxproj is missing expected line: {pattern}")
    at = match.end()
    if text[at : at + 1] == "\n":
        at += 1
    return text[:at] + addition + text[at:]


def _ref_line(indent: str, file_id: str, lang: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9]+", lang):
        name = lang
        path = f"{lang}.lproj/InfoPlist.strings"
    else:
        name = f'"{lang}"'
        path = f'"{lang}.lproj/InfoPlist.strings"'
    return (
        f"{indent}{file_id} /* {lang} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = text.plist.strings; name = {name}; "
        f'path = {path}; sourceTree = "<group>"; }};\n'
    )


def folder_names(lang: str) -> tuple[str, ...]:
    return FOLDER_NAMES.get(lang, (lang,))


def resolve_lang(text: str, app_src: Path, lang: str) -> str:
    for name in folder_names(lang):
        if _file_ref_id(text, name) or (app_src / f"{name}.lproj").is_dir():
            return name
    return folder_names(lang)[0]


def used_name(text: str, lang: str) -> str:
    for name in folder_names(lang):
        if _file_ref_id(text, name):
            return name
    return folder_names(lang)[0]


def write_lproj(app_src: Path, text: str) -> None:
    if not LPROJ_SRC.is_dir():
        raise SystemExit(f"missing {LPROJ_SRC}")
    for lang in LOCALES:
        source = LPROJ_SRC / f"{lang}.lproj" / "InfoPlist.strings"
        if not source.is_file():
            raise SystemExit(f"missing {source}")
        strings = source.read_text(encoding="utf-8")
        if "CFBundleDisplayName" not in strings:
            raise SystemExit(f"{source} has no CFBundleDisplayName")
        folder = app_src / f"{resolve_lang(text, app_src, lang)}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "InfoPlist.strings").write_text(strings, encoding="utf-8")


def _has_all_localizations(data: dict) -> bool:
    present = {str(item) for item in data.get("CFBundleLocalizations", [])}
    for lang in LOCALES:
        if present.isdisjoint(set(folder_names(lang))):
            return False
    return True


def patch_info_plist(app_src: Path) -> None:
    for plist_path in app_src.glob("*Info.plist"):
        with plist_path.open("rb") as handle:
            data = plistlib.load(handle)
        if not isinstance(data, dict):
            raise SystemExit(f"{plist_path} is not a plist dictionary")
        if _has_all_localizations(data):
            continue
        data["CFBundleLocalizations"] = list(LOCALES)
        with plist_path.open("wb") as handle:
            plistlib.dump(data, handle, sort_keys=False)


def patch_pbxproj(text: str) -> str:
    en_line = re.search(
        r"^(\t*)([A-F0-9]{24}) /\* en \*/ = \{isa = PBXFileReference;[^}]*path = en\.lproj/InfoPlist\.strings;.*\};\s*$",
        text,
        re.M,
    )
    if not en_line:
        raise SystemExit("pbxproj has no en.lproj/InfoPlist.strings file reference")
    indent = en_line.group(1)
    en_text = en_line.group(0)
    for lang in LOCALES:
        if lang == "en" or any(_file_ref_id(text, name) for name in folder_names(lang)):
            continue
        name = folder_names(lang)[0]
        line = _ref_line(indent, FILE_IDS[lang], name)
        text = _insert_after(text, re.escape(en_text), line)

    variant = re.search(
        r"(/\* Begin PBXVariantGroup section \*/.*?/\* End PBXVariantGroup section \*/)",
        text,
        re.S,
    )
    if not variant:
        raise SystemExit("pbxproj has no PBXVariantGroup for InfoPlist.strings")
    block = variant.group(1)
    updated = block
    for lang in LOCALES:
        if lang == "en":
            continue
        name = used_name(text, lang)
        file_id = _file_ref_id(text, name)
        if not file_id:
            raise SystemExit(f"no file reference for {lang}.lproj after patching")
        if re.search(rf"{file_id} /\* {re.escape(name)} \*/", updated):
            continue
        child = f"\t\t\t\t{file_id} /* {name} */,\n"
        marker = re.search(r"(/\* en \*/,)\n", updated)
        if not marker:
            raise SystemExit("variant group has no en child")
        updated = updated[: marker.end()] + child + updated[marker.end() :]
    text = text[: variant.start(1)] + updated + text[variant.end(1) :]

    regions = re.search(r"knownRegions = \((.*?)\);", text, re.S)
    if not regions:
        raise SystemExit("pbxproj has no knownRegions")
    body = regions.group(1)
    lines = body.splitlines()
    present: set[str] = set()
    indent = "\t\t\t\t"
    for line in lines:
        entry = re.match(r'\s*"?([A-Za-z0-9_-]+)"?\s*,\s*$', line)
        if entry:
            present.add(entry.group(1))
            if entry.group(1) == "Base":
                indent = re.match(r"(\s*)", line).group(1)
    wanted = [used_name(text, lang) for lang in LOCALES]
    extra = [f"{indent}{_quoted(name)}," for name in wanted if name not in present]
    if extra:
        rebuilt: list[str] = []
        inserted = False
        for line in lines:
            rebuilt.append(line)
            if re.match(r"\s*Base\s*,\s*$", line):
                rebuilt.extend(extra)
                inserted = True
        if not inserted:
            raise SystemExit("knownRegions has no Base")
        text = text[: regions.start(1)] + "\n".join(rebuilt) + text[regions.end(1) :]
    return text


def app_source(pbx: Path) -> Path:
    project_dir = pbx.parent.parent
    name = pbx.parent.name.removesuffix(".xcodeproj")
    candidate = project_dir / name
    if candidate.is_dir():
        return candidate
    matches = [path.parent for path in project_dir.glob("*/en.lproj")]
    if len(matches) == 1:
        return matches[0]
    raise SystemExit(f"could not find the app source next to {pbx}")


def localize_tree(root: Path) -> int:
    projects = [
        pbx
        for pbx in root.rglob("project.pbxproj")
        if "Pods" not in pbx.parts and pbx.parent.suffix == ".xcodeproj"
    ]
    if not projects:
        raise SystemExit(f"no .xcodeproj under {root}")
    changed = 0
    for pbx in projects:
        src = app_source(pbx)
        original = pbx.read_text(encoding="utf-8")
        write_lproj(src, original)
        patch_info_plist(src)
        updated = patch_pbxproj(original)
        if updated != original:
            pbx.write_text(updated, encoding="utf-8")
            changed += 1
            print(f"Added store localizations in {pbx}")
        else:
            print(f"Localizations already present in {pbx}")
        print(f"Wrote {', '.join(lang + '.lproj' for lang in LOCALES)} under {src}")
    return changed


def self_test() -> int:
    for lang in LOCALES:
        source = LPROJ_SRC / f"{lang}.lproj" / "InfoPlist.strings"
        if not source.is_file() or "CFBundleDisplayName" not in source.read_text(encoding="utf-8"):
            print(f"missing source strings for {lang}", file=sys.stderr)
            return 1
    fixture = (
        "knownRegions = (\n"
        "\t\t\t\ten,\n"
        "\t\t\t\tBase,\n"
        "\t\t\t);\n"
        "\tAABBCCDDEEFF001122334455 /* en */ = {isa = PBXFileReference; "
        "lastKnownFileType = text.plist.strings; name = en; "
        'path = en.lproj/InfoPlist.strings; sourceTree = "<group>"; };\n'
        "/* Begin PBXVariantGroup section */\n"
        "\t\t11223344556677889900AABB /* InfoPlist.strings */ = {\n"
        "\t\t\tisa = PBXVariantGroup;\n"
        "\t\t\tchildren = (\n"
        "\t\t\t\tAABBCCDDEEFF001122334455 /* en */,\n"
        "\t\t\t);\n"
        "\t\t\tname = InfoPlist.strings;\n"
        '\t\t\tsourceTree = "<group>";\n'
        "\t\t};\n"
        "/* End PBXVariantGroup section */\n"
    )
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        app = root / "SewLens"
        (app / "en.lproj").mkdir(parents=True)
        (app / "en.lproj" / "InfoPlist.strings").write_text("OLD\n", encoding="utf-8")
        with (app / "Info.plist").open("wb") as handle:
            plistlib.dump({"CFBundleName": "SewLens"}, handle)
        proj = root / "SewLens.xcodeproj"
        proj.mkdir()
        pbx = proj / "project.pbxproj"
        pbx.write_text(fixture, encoding="utf-8")
        localize_tree(root)
        text = pbx.read_text(encoding="utf-8")
        for lang in LOCALES:
            strings = app / f"{lang}.lproj" / "InfoPlist.strings"
            if "CFBundleDisplayName" not in strings.read_text(encoding="utf-8"):
                print(f"strings not copied for {lang}", file=sys.stderr)
                return 1
            if f"/* {lang} */" not in text:
                print(f"pbxproj missing {lang}", file=sys.stderr)
                return 1
        with (app / "Info.plist").open("rb") as handle:
            data = plistlib.load(handle)
        if list(data.get("CFBundleLocalizations", [])) != list(LOCALES):
            print(f"plist localizations {data.get('CFBundleLocalizations')}", file=sys.stderr)
            return 1
        localize_tree(root)
        again = pbx.read_text(encoding="utf-8")
        if again != text:
            print("second run changed the pbxproj", file=sys.stderr)
            return 1
    print("add_store_localizations self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 2:
        print("usage: add_store_localizations.py <build-root> | --self-test", file=sys.stderr)
        return 1
    localize_tree(Path(argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
