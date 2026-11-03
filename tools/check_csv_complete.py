#!/usr/bin/env python3
"""Fail unless every i18n key has a non-empty value in all 8 locales."""

from __future__ import annotations

import csv
import sys
from pathlib import Path


COLUMNS = ("en", "de", "fr", "es", "pt_BR", "ja", "it", "nl")
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CSV = ROOT / "i18n" / "strings.csv"


def check(path: Path) -> list[str]:
    errors: list[str] = []
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            return [f"{path}: missing header"]
        missing = [name for name in COLUMNS if name not in reader.fieldnames]
        if missing:
            errors.append(f"{path}: header missing {', '.join(missing)}")
            return errors
        if "keys" not in reader.fieldnames:
            errors.append(f"{path}: header missing keys column")
            return errors
        seen: set[str] = set()
        for line_no, row in enumerate(reader, start=2):
            key = (row.get("keys") or "").strip()
            if key == "":
                errors.append(f"{path}:{line_no}: empty key")
                continue
            if key in seen:
                errors.append(f"{path}:{line_no}: duplicate key {key}")
            seen.add(key)
            for column in COLUMNS:
                value = (row.get(column) or "").strip()
                if value == "":
                    errors.append(f"{path}:{line_no}: {key} missing {column}")
        if not seen:
            errors.append(f"{path}: no keys")
    return errors


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_CSV
    if not path.is_file():
        print(f"missing {path}", file=sys.stderr)
        return 1
    errors = check(path)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"{path}: all keys have en, de, fr, es, pt_BR, ja, it, nl")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
