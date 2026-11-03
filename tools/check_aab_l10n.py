#!/usr/bin/env python3
"""Fail unless an AAB has values-<lang> resources for all 8 store languages.

Runs `bundletool dump resources` and also lists the zip entries. pt-BR matches
values-pt-rBR, values-b+pt+BR, or values-pt-BR.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


REQUIRED = {
    "en": ("values-en",),
    "de": ("values-de",),
    "fr": ("values-fr",),
    "es": ("values-es",),
    "pt-BR": ("values-pt-rBR", "values-b+pt+BR", "values-pt-BR"),
    "ja": ("values-ja",),
    "it": ("values-it",),
    "nl": ("values-nl",),
}

# bundletool 1.18 prints compiled configs as locale: "de" (resources.pb, no values-de/ path).
# Older dumps and unzipped resources use values-<lang> or (de).
DUMP_TOKENS = {
    "en": ('locale: "en"', "values-en", "(en)"),
    "de": ('locale: "de"', "values-de", "(de)"),
    "fr": ('locale: "fr"', "values-fr", "(fr)"),
    "es": ('locale: "es"', "values-es", "(es)"),
    "pt-BR": (
        'locale: "pt-BR"',
        'locale: "pt-rBR"',
        "values-pt-rBR",
        "values-b+pt+BR",
        "values-pt-BR",
        "(pt-rBR)",
        "(b+pt+BR)",
    ),
    "ja": ('locale: "ja"', "values-ja", "(ja)"),
    "it": ('locale: "it"', "values-it", "(it)"),
    "nl": ('locale: "nl"', "values-nl", "(nl)"),
}


def zip_has(names: list[str], qualifiers: tuple[str, ...]) -> bool:
    for name in names:
        normalized = name.replace("\\", "/")
        for qualifier in qualifiers:
            if f"/{qualifier}/" in f"/{normalized}":
                return True
    return False


def missing(names: list[str], dump: str) -> list[str]:
    errors: list[str] = []
    for lang, qualifiers in REQUIRED.items():
        in_dump = any(token in dump for token in DUMP_TOKENS[lang])
        in_zip = zip_has(names, qualifiers)
        if not in_dump and not in_zip:
            errors.append(f"AAB missing values-{lang} resource (bundletool dump has no {lang} config)")
    return errors


def bundletool_command(aab: Path) -> list[str]:
    prefix = os.environ.get("BUNDLETOOL_PREFIX")
    if prefix:
        return prefix.split("|") + ["dump", "resources", f"--bundle={aab}"]
    return ["bundletool", "dump", "resources", f"--bundle={aab}"]


def dump_resources(aab: Path) -> str:
    try:
        result = subprocess.run(
            bundletool_command(aab),
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit(f"bundletool not found: {exc}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "bundletool dump resources failed").strip()
        raise SystemExit(detail)
    return result.stdout


def check_aab(path: Path) -> list[str]:
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
    return missing(names, dump_resources(path))


def self_test() -> int:
    langs = ("en", "de", "fr", "es", "pt-rBR", "ja", "it", "nl")

    def build(skip: str | None) -> Path:
        tmp = Path(tempfile.mkdtemp()) / "SewLens.aab"
        with zipfile.ZipFile(tmp, "w") as archive:
            for lang in langs:
                if lang == skip:
                    continue
                archive.writestr(
                    f"base/res/values-{lang}/strings.xml",
                    "<resources><string name=\"app_name\">SewLens</string></resources>",
                )
        return tmp

    def fake_for(text: str) -> str:
        path = Path(tempfile.mkdtemp()) / "bundletool_fake.py"
        path.write_text("print(" + repr(text) + ")\n", encoding="utf-8")
        return f"{sys.executable}|{path}"

    all_locales = "\n".join(
        f'locale: "{code}"' for code in ("en", "de", "fr", "es", "pt-BR", "ja", "it", "nl")
    )
    os.environ["BUNDLETOOL_PREFIX"] = fake_for(all_locales)
    good = check_aab(build(None))
    if good:
        print("self-test expected a complete AAB to pass:", good, file=sys.stderr)
        return 1
    os.environ["BUNDLETOOL_PREFIX"] = fake_for(all_locales.replace('locale: "ja"\n', ""))
    bad = check_aab(build("ja"))
    if not any("ja" in error for error in bad):
        print("self-test expected missing ja to fail:", bad, file=sys.stderr)
        return 1
    compiled = Path(tempfile.mkdtemp()) / "compiled.aab"
    with zipfile.ZipFile(compiled, "w") as archive:
        archive.writestr("base/resources.pb", b"compiled")
    os.environ["BUNDLETOOL_PREFIX"] = fake_for(all_locales)
    compiled_errors = check_aab(compiled)
    if compiled_errors:
        print("self-test expected compiled resources.pb to pass:", compiled_errors, file=sys.stderr)
        return 1
    print("check_aab_l10n self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 2:
        print("usage: check_aab_l10n.py <app.aab> | --self-test", file=sys.stderr)
        return 1
    path = Path(argv[1])
    if not path.is_file():
        print(f"missing {path}", file=sys.stderr)
        return 1
    errors = check_aab(path)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"{path}: values-<lang> resources for {', '.join(REQUIRED)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
