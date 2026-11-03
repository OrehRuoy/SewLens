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


def main() -> int:
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
    print(f"Firebase Android config wired for {PACKAGE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
