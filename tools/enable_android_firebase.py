#!/usr/bin/env python3
"""Wire google-services.json into the Godot Android gradle template.

Godot's --install-android-build-template replaces android/build, so run this
after that install. The durable copy is android/google-services.json
(gitignored). The export reads android/build/google-services.json.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path


PACKAGE = "com.sewlens.app"
ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "android" / "build"
DURABLE = ROOT / "android" / "google-services.json"
DEST = BUILD / "google-services.json"


def packages(path: Path) -> list[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    found: list[str] = []
    for client in data.get("client", []):
        info = client.get("client_info", {}).get("android_client_info", {})
        name = info.get("package_name")
        if isinstance(name, str) and name:
            found.append(name)
    return found


def patch_settings(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "com.google.gms.google-services" in text:
        return
    needle = "id 'org.jetbrains.kotlin.android' version versions.kotlinVersion\n"
    insert = needle + "        id 'com.google.gms.google-services' version '4.4.4'\n"
    if needle not in text:
        raise SystemExit(f"settings.gradle is missing the Kotlin plugin line: {path}")
    path.write_text(text.replace(needle, insert, 1), encoding="utf-8", newline="\n")


def patch_config(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "hasGoogleServicesClientForExportPackage" in text:
        return
    needle = "ext.getExportVersionCode = { ->"
    helper = """// True when google-services.json lists a client for the current Godot export package.
ext.hasGoogleServicesClientForExportPackage = { ->
    File googleServicesFile = file("google-services.json")
    if (!googleServicesFile.isFile()) {
        return false
    }
    String exportPackage = getExportPackageName()
    try {
        def json = new groovy.json.JsonSlurper().parse(googleServicesFile)
        if (json.client == null) {
            return false
        }
        for (def client : json.client) {
            String pkg = client?.client_info?.android_client_info?.package_name
            if (exportPackage == pkg) {
                return true
            }
        }
    } catch (Exception e) {
        logger.warn("Firebase: failed to parse google-services.json: ${e.message}")
        return false
    }
    return false
}

"""
    if needle not in text:
        raise SystemExit(f"config.gradle is missing getExportVersionCode: {path}")
    path.write_text(text.replace(needle, helper + needle, 1), encoding="utf-8", newline="\n")


def patch_build(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if "enableGoogleServices" in text:
        return
    needle = """plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

apply from: 'config.gradle'

"""
    insert = f"""plugins {{
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
    id 'com.google.gms.google-services' apply false
    id 'com.google.firebase.crashlytics' apply false
}}

apply from: 'config.gradle'

def hasGoogleServicesFile = file("google-services.json").exists()
def enableGoogleServices = hasGoogleServicesFile && hasGoogleServicesClientForExportPackage()
def exportPackageName = getExportPackageName()
if (enableGoogleServices) {{
    apply plugin: 'com.google.gms.google-services'
    logger.lifecycle("Firebase: Google Services plugin ENABLED for '${{exportPackageName}}'.")
}} else if (hasGoogleServicesFile) {{
    logger.lifecycle("Firebase: no google-services client for '${{exportPackageName}}'; Google Services plugin disabled for this build.")
    if (exportPackageName == "{PACKAGE}") {{
        throw new GradleException(
            "Release package '${{exportPackageName}}' has no matching client in android/build/google-services.json."
        )
    }}
}} else {{
    logger.lifecycle("Firebase: google-services.json not found in android/build; Google Services plugin disabled for this build.")
    if (exportPackageName == "{PACKAGE}") {{
        throw new GradleException(
            "Missing android/build/google-services.json for release package '${{exportPackageName}}'."
        )
    }}
}}

"""
    if needle not in text:
        raise SystemExit(f"build.gradle plugins block was not the stock Godot template: {path}")
    path.write_text(text.replace(needle, insert, 1), encoding="utf-8", newline="\n")


CRASHLYTICS_SETTINGS = "        id 'com.google.firebase.crashlytics' version '3.0.3'\n"
CRASHLYTICS_APPLY = "    apply plugin: 'com.google.firebase.crashlytics'\n"


def patch_crashlytics(settings: Path, build: Path) -> None:
    stext = settings.read_text(encoding="utf-8")
    if "com.google.firebase.crashlytics" not in stext:
        needle = "id 'com.google.gms.google-services' version '4.4.4'\n"
        if needle not in stext:
            raise SystemExit(f"google-services plugin line missing: {settings}")
        stext = stext.replace(needle, needle + CRASHLYTICS_SETTINGS, 1)
        settings.write_text(stext, encoding="utf-8", newline="\n")
    btext = build.read_text(encoding="utf-8")
    # The plugins block already names Crashlytics. Match the apply line so that declaration is not treated as done.
    if CRASHLYTICS_APPLY not in btext:
        needle = "    apply plugin: 'com.google.gms.google-services'\n"
        if needle not in btext:
            raise SystemExit(f"google-services apply line missing: {build}")
        btext = btext.replace(needle, needle + CRASHLYTICS_APPLY, 1)
        build.write_text(btext, encoding="utf-8", newline="\n")


def self_test() -> int:
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        settings = root / "settings.gradle"
        build = root / "build.gradle"
        settings.write_text("id 'com.google.gms.google-services' version '4.4.4'\n", encoding="utf-8")
        build.write_text("    apply plugin: 'com.google.gms.google-services'\n", encoding="utf-8")
        patch_crashlytics(settings, build)
        patch_crashlytics(settings, build)
        stext = settings.read_text(encoding="utf-8")
        btext = build.read_text(encoding="utf-8")
        if stext.count(CRASHLYTICS_SETTINGS) != 1 or "apply false" in stext or btext.count(CRASHLYTICS_APPLY) != 1:
            print("self-test failed to add Crashlytics once", file=sys.stderr)
            return 1
        stock = root / "stock.gradle"
        stock.write_text(
            "plugins {\n    id 'com.android.application'\n    id 'org.jetbrains.kotlin.android'\n}\n\napply from: 'config.gradle'\n\n",
            encoding="utf-8",
        )
        patch_build(stock)
        patch_build(stock)
        patch_crashlytics(settings, stock)
        patch_crashlytics(settings, stock)
        patched = stock.read_text(encoding="utf-8")
        fresh_settings = settings.read_text(encoding="utf-8")
        if patched.count("id 'com.google.firebase.crashlytics' apply false") != 1 or patched.count(CRASHLYTICS_APPLY) != 1:
            print("self-test failed to keep the build.gradle Crashlytics lines idempotent", file=sys.stderr)
            return 1
        if fresh_settings.count(CRASHLYTICS_SETTINGS) != 1:
            print("self-test failed to keep the settings.gradle Crashlytics line idempotent", file=sys.stderr)
            return 1
    print("enable_android_firebase crashlytics self-test OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv if argv is None else argv)
    if "--self-test" in args:
        return self_test()
    if not BUILD.is_dir():
        print("missing android/build; install the Android build template first", file=sys.stderr)
        return 1
    if DURABLE.is_file():
        shutil.copy2(DURABLE, DEST)
    if not DEST.is_file():
        print("missing android/build/google-services.json", file=sys.stderr)
        return 1
    found = packages(DEST)
    if PACKAGE not in found:
        print(f"google-services.json has no Android client for {PACKAGE}", file=sys.stderr)
        return 1
    patch_settings(BUILD / "settings.gradle")
    patch_config(BUILD / "config.gradle")
    patch_build(BUILD / "build.gradle")
    patch_crashlytics(BUILD / "settings.gradle", BUILD / "build.gradle")
    print(f"Firebase Android config wired for {PACKAGE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
