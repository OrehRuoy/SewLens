#!/usr/bin/env python3
"""Fail unless Play Billing is declared for the Android export, not only compileOnly.

Checks the plugin manifest, the Godot export dependency, the packaged plugin AAR,
and an exported AAB when one is passed. The AAB manifest is protobuf, so this
searches the decoded strings rather than relying on aapt2 dump xmltree.
"""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "addons" / "sewlens_android" / "android" / "src" / "main" / "AndroidManifest.xml"
EXPORT_PLUGIN = ROOT / "addons" / "sewlens_android" / "export_plugin.gd"
LIBRARY_GRADLE = ROOT / "addons" / "sewlens_android" / "android" / "build.gradle"
PLUGIN_AAR = ROOT / "addons" / "sewlens_android" / "sewlens_android.aar"
BILLING = "com.android.billingclient:billing:8.3.0"
PERMISSION = "com.android.vending.BILLING"
PACKAGE = "com.android.vending"
BIND = "com.android.vending.billing.InAppBillingService.BIND"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def require(errors: list[str], ok: bool, message: str) -> None:
    if not ok:
        errors.append(message)


def check_sources(errors: list[str]) -> None:
    manifest = text(MANIFEST)
    require(errors, PERMISSION in manifest, f"{MANIFEST.name} is missing {PERMISSION}")
    require(errors, f'android:name="{PACKAGE}"' in manifest, f"{MANIFEST.name} is missing <package android:name=\"{PACKAGE}\"/>")
    require(errors, BIND in manifest, f"{MANIFEST.name} is missing {BIND}")
    export = text(EXPORT_PLUGIN)
    require(errors, BILLING in export, f"export_plugin.gd does not package {BILLING}")
    require(errors, "_get_android_dependencies" in export, "export_plugin.gd is missing _get_android_dependencies")
    gradle = text(LIBRARY_GRADLE)
    require(
        errors,
        "compileOnly 'com.android.billingclient:billing:8.3.0'" in gradle,
        "the plugin library should compile against billing 8.3.0",
    )
    require(
        errors,
        "implementation 'com.android.billingclient:billing" not in gradle,
        "billing must be packaged by the app export, not shaded into the plugin AAR",
    )


def readable(data: bytes) -> str:
    return data.decode("latin1") + "\n" + data.replace(b"\x00", b"").decode("latin1")


def contains_package_query(data: bytes) -> bool:
    """True when com.android.vending is its own string, not a prefix of BILLING or the bind action."""
    needle = b"com.android.vending"
    start = 0
    while True:
        index = data.find(needle, start)
        if index < 0:
            return False
        after = index + len(needle)
        if after >= len(data) or data[after] != ord("."):
            return True
        start = after


def class_text(archive: zipfile.ZipFile) -> str:
    parts: list[str] = []
    for name in archive.namelist():
        if name.endswith("classes.jar"):
            inner = zipfile.ZipFile(archive.open(name))
            with inner:
                parts.extend(readable(inner.read(entry)) for entry in inner.namelist() if entry.endswith(".class"))
        elif name.endswith(".dex"):
            parts.append(readable(archive.read(name)))
    return "\n".join(parts)


def check_archive(errors: list[str], label: str, path: Path, *, want_client: bool, want_log: bool) -> None:
    if not path.is_file():
        errors.append(f"{label} is missing: {path}")
        return
    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile:
        errors.append(f"{label} is not a zip: {path}")
        return
    with archive:
        names = archive.namelist()
        manifest_bytes = b"\n".join(archive.read(name) for name in names if name.endswith("AndroidManifest.xml"))
        manifest = readable(manifest_bytes)
        properties = "\n".join(readable(archive.read(name)) for name in names if name.endswith(".properties"))
        classes = class_text(archive) if want_client or want_log else ""
    require(errors, PERMISSION in manifest, f"{label} is missing {PERMISSION}")
    require(errors, BIND in manifest, f"{label} is missing {BIND}")
    require(errors, contains_package_query(manifest_bytes), f"{label} is missing package query {PACKAGE}")
    if want_client:
        require(errors, "Lcom/android/billingclient/api/BillingClient;" in classes, f"{label} does not contain BillingClient")
        require(errors, "billing_client=8.3.0" in properties or "version=8.3.0" in properties, f"{label} does not contain billing 8.3.0")
    if want_log:
        require(errors, "SEWLENS_BILLING" in classes, f"{label} is missing the SEWLENS_BILLING log tag")
        require(errors, "startConnection returned" in classes, f"{label} is missing the startConnection return log")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--aab", type=Path, help="exported Android App Bundle to inspect")
    args = parser.parse_args()
    errors: list[str] = []
    check_sources(errors)
    check_archive(errors, "plugin AAR", PLUGIN_AAR, want_client=False, want_log=True)
    if args.aab is not None:
        check_archive(errors, "AAB", args.aab, want_client=True, want_log=False)
    if errors:
        print("android billing check failed:")
        for error in errors:
            print(f"  - {error}")
        return 1
    print("android billing check passed")
    if args.aab is not None:
        print(f"  AAB {args.aab}")
    print(f"  AAR {PLUGIN_AAR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
