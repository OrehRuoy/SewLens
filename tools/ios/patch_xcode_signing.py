#!/usr/bin/env python3
"""Patch Godot-exported Xcode projects for App Store CI signing.

- App target: Manual + Apple Distribution (+ App Store profile when present)
- Pods targets: disable code signing (profiles are not supported on pods)
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


def patch_pods(text: str) -> str:
	for key, val in (
		("CODE_SIGNING_ALLOWED", "NO"),
		("CODE_SIGNING_REQUIRED", "NO"),
		("CODE_SIGN_STYLE", "Automatic"),
	):
		text = re.sub(rf"{key} = [^;]+;", f"{key} = {val};", text)
	return text


def patch_app(text: str, profile_name: str) -> str:
	text = text.replace("CODE_SIGN_STYLE = Automatic;", "CODE_SIGN_STYLE = Manual;")
	text = text.replace(
		'CODE_SIGN_IDENTITY = "Apple Development";',
		'CODE_SIGN_IDENTITY = "Apple Distribution";',
	)
	text = text.replace('CODE_SIGN_IDENTITY = "-";', 'CODE_SIGN_IDENTITY = "Apple Distribution";')
	if "PROVISIONING_PROFILE_SPECIFIER" in text:
		text = re.sub(
			r'PROVISIONING_PROFILE_SPECIFIER = "[^"]*";',
			f'PROVISIONING_PROFILE_SPECIFIER = "{profile_name}";',
			text,
		)
	return text


def main() -> int:
	if len(sys.argv) < 3:
		print("usage: patch_xcode_signing.py <build-root> <profile-name>", file=sys.stderr)
		return 1
	root = Path(sys.argv[1])
	profile_name = sys.argv[2]
	changed = 0
	for pbx in root.rglob("project.pbxproj"):
		text = pbx.read_text(encoding="utf-8")
		orig = text
		if "Pods" in pbx.parts:
			text = patch_pods(text)
			label = "Disabled Pod signing"
		else:
			text = patch_app(text, profile_name)
			label = "Patched app signing"
		if text != orig:
			pbx.write_text(text, encoding="utf-8")
			print(f"{label} in {pbx}")
			changed += 1
	print(f"Signing patch complete ({changed} project file(s) updated).")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
