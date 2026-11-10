#!/usr/bin/env python3
"""Fail unless an IPA ships all 8 SewLens store languages.

Unzips the IPA, reads Payload/*.app/Info.plist with plistlib, and requires
CFBundleLocalizations plus <lang>.lproj/InfoPlist.strings for each language.
Info.plist and every InfoPlist.strings must carry the camera and photo
library usage text; iOS ends the app on first camera use without it.
pt-BR and pt_BR are both accepted.
"""

from __future__ import annotations

import io
import plistlib
import re
import sys
import tempfile
import zipfile
from pathlib import Path


LANGS = ("en", "de", "fr", "es", "pt-BR", "ja", "it", "nl")
USAGE_KEYS = ("NSCameraUsageDescription", "NSPhotoLibraryUsageDescription")


def plist_names(lang: str) -> set[str]:
    if lang == "pt-BR":
        return {"pt-BR", "pt_BR"}
    return {lang}


def lproj_dirs(lang: str) -> set[str]:
    if lang == "pt-BR":
        return {"pt-BR.lproj", "pt_BR.lproj"}
    return {f"{lang}.lproj"}


def app_info_name(names: list[str]) -> str:
    matches = [
        name
        for name in names
        if name.startswith("Payload/")
        and name.endswith(".app/Info.plist")
        and name.count("/") == 2
    ]
    if len(matches) != 1:
        raise SystemExit(f"expected one Payload/*.app/Info.plist, found {matches}")
    return matches[0]


def strings_keys(data: bytes) -> set[str]:
    """Keys of a .strings file: binary/XML plist (as Xcode ships it) or text."""
    try:
        parsed = plistlib.loads(data)
        if isinstance(parsed, dict):
            return {str(key) for key in parsed}
    except Exception:
        pass
    for encoding in ("utf-8-sig", "utf-16"):
        try:
            text = data.decode(encoding)
            break
        except UnicodeDecodeError:
            continue
    else:
        return set()
    return set(re.findall(r'^\s*"?([A-Za-z0-9_]+)"?\s*=', text, re.M))


def missing(names: list[str], plist: dict, read=None) -> list[str]:
    errors: list[str] = []
    for key in USAGE_KEYS:
        if not str(plist.get(key, "")).strip():
            errors.append(f"Info.plist missing {key}")
    localizations = plist.get("CFBundleLocalizations")
    if not isinstance(localizations, list):
        errors.append("CFBundleLocalizations missing or not an array")
        present = set()
    else:
        present = {str(item) for item in localizations}
    info = app_info_name(names) if any(name.endswith(".app/Info.plist") for name in names) else ""
    prefix = info[: -len("Info.plist")] if info else ""
    for lang in LANGS:
        if present.isdisjoint(plist_names(lang)):
            errors.append(f"CFBundleLocalizations missing {lang}")
        if prefix == "":
            continue
        found = ""
        for folder in lproj_dirs(lang):
            strings = f"{prefix}{folder}/InfoPlist.strings"
            if strings in names:
                found = strings
                break
        if not found:
            errors.append(f"missing {prefix}<{lang}>.lproj/InfoPlist.strings")
            continue
        if read is not None:
            keys = strings_keys(read(found))
            for key in USAGE_KEYS:
                if key not in keys:
                    errors.append(f"{found} missing {key}")
    return errors


def check_ipa(path: Path) -> list[str]:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        info_name = app_info_name(names)
        with archive.open(info_name) as handle:
            plist = plistlib.load(handle)
        if not isinstance(plist, dict):
            return ["Info.plist is not a dictionary"]
        return missing(names, plist, archive.read)


def self_test() -> int:
    usage = {key: "Used to photograph a garment." for key in USAGE_KEYS}

    def build(include_ja: bool, pt_folder: str, de_camera: bool = True) -> Path:
        buf = io.BytesIO()
        langs = [lang for lang in LANGS if include_ja or lang != "ja"]
        plist = {"CFBundleLocalizations": langs, "CFBundleDisplayName": "SewLens", **usage}
        with zipfile.ZipFile(buf, "w") as archive:
            archive.writestr("Payload/SewLens.app/Info.plist", plistlib.dumps(plist))
            for lang in langs:
                folder = pt_folder if lang == "pt-BR" else f"{lang}.lproj"
                strings = {"CFBundleDisplayName": "SewLens", **usage}
                if lang == "de" and not de_camera:
                    del strings["NSCameraUsageDescription"]
                if lang == "fr":
                    body = "".join(f'{key} = "{value}";\n' for key, value in strings.items()).encode("utf-8")
                else:
                    body = plistlib.dumps(strings, fmt=plistlib.FMT_BINARY)
                archive.writestr(f"Payload/SewLens.app/{folder}/InfoPlist.strings", body)
        tmp = Path(tempfile.mkdtemp()) / "SewLens.ipa"
        tmp.write_bytes(buf.getvalue())
        return tmp

    good = build(True, "pt-BR.lproj")
    errors = check_ipa(good)
    if errors:
        print("self-test expected a good IPA to pass:", errors, file=sys.stderr)
        return 1
    alias = build(True, "pt_BR.lproj")
    errors = check_ipa(alias)
    if errors:
        print("self-test expected pt_BR to pass:", errors, file=sys.stderr)
        return 1
    bad = build(False, "pt-BR.lproj")
    errors = check_ipa(bad)
    if not any("ja" in error for error in errors):
        print("self-test expected missing ja to fail:", errors, file=sys.stderr)
        return 1
    no_camera = build(True, "pt-BR.lproj", de_camera=False)
    errors = check_ipa(no_camera)
    if errors != ["Payload/SewLens.app/de.lproj/InfoPlist.strings missing NSCameraUsageDescription"]:
        print("self-test expected missing de camera text to fail:", errors, file=sys.stderr)
        return 1
    for lang in LANGS:
        source = Path(__file__).resolve().parents[1] / "ios" / "InfoPlist" / f"{lang}.lproj" / "InfoPlist.strings"
        keys = strings_keys(source.read_bytes())
        absent = [key for key in USAGE_KEYS if key not in keys]
        if absent:
            print(f"{source} missing {', '.join(absent)}", file=sys.stderr)
            return 1
    print("check_ipa_l10n self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 2:
        print("usage: check_ipa_l10n.py <app.ipa> | --self-test", file=sys.stderr)
        return 1
    path = Path(argv[1])
    if not path.is_file():
        print(f"missing {path}", file=sys.stderr)
        return 1
    errors = check_ipa(path)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"{path}: CFBundleLocalizations and .lproj InfoPlist.strings for {', '.join(LANGS)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
