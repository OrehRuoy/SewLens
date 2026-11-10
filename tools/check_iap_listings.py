#!/usr/bin/env python3
"""Check store listing copy for the two SewLens in-app products.

Display names stay within 30 characters and descriptions within 45, which is
Apple's IAP limit and the length both stores use. The app must not hard-code
a price; the USD amounts live only in this listing file for the store setup.
The review screenshot is regenerated with `godot --path . -s res://test/capture_review.gd`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

LOCALES = ["en", "de", "fr", "es", "pt-BR", "ja", "it", "nl"]
PRODUCTS = {
    "orehruoy.sewlens.credit": "consumable",
    "orehruoy.sewlens.unlimited": "non-consumable",
}
NAME_LIMIT = 30
DESCRIPTION_LIMIT = 45
ROOT = Path(__file__).resolve().parents[1]
LISTINGS = ROOT / "store" / "iap" / "listings.json"
REVIEW = ROOT / "store" / "iap" / "review.png"
STRINGS = ROOT / "i18n" / "strings.csv"
FORBIDDEN = ("$2.99", "$24.99", "2,99", "24,99")
## Every purchase string and the purchase screen are scanned for hard-coded prices.
REQUIRED = ("pay_credit", "pay_unlimited", "pay_price_loading", "pay_prices_failed", "pay_legal", "btn_buy", "btn_restore")
PRICE_SCANNED = ("pay_", "btn_buy", "btn_get_unlimited", "btn_see_options", "home_out_")
PAYWALL = ROOT / "scripts" / "screens" / "paywall_screen.gd"
## App Store Connect rejects in-app purchase review screenshots smaller than this.
REVIEW_MIN = (640, 920)


def problems(listings: dict, review: bytes, strings: str, sources: dict | None = None) -> list[str]:
    found = []
    products = listings.get("products", [])
    ids = [item.get("id") for item in products]
    if ids != list(PRODUCTS):
        found.append(f"product ids are {ids}")
    for item in products:
        if PRODUCTS.get(item.get("id")) != item.get("type"):
            found.append(f"{item.get('id')} type is {item.get('type')}")
        names = item.get("listings", {})
        if list(names) != LOCALES:
            found.append(f"{item.get('id')} locales are {list(names)}")
        for locale, copy in names.items():
            name = str(copy.get("name", ""))
            description = str(copy.get("description", ""))
            if not name or len(name) > NAME_LIMIT:
                found.append(f"{item.get('id')} {locale} name length {len(name)}")
            if not description or len(description) > DESCRIPTION_LIMIT:
                found.append(f"{item.get('id')} {locale} description length {len(description)}")
    if not review.startswith(b"\x89PNG\r\n\x1a\n") or len(review) < 1000:
        found.append("review screenshot is missing")
    else:
        width, height = int.from_bytes(review[16:20], "big"), int.from_bytes(review[20:24], "big")
        if width < REVIEW_MIN[0] or height < REVIEW_MIN[1]:
            found.append(f"review screenshot is {width}x{height}, below {REVIEW_MIN[0]}x{REVIEW_MIN[1]}")
    rows = {line.split(",", 1)[0]: line for line in strings.splitlines() if "," in line}
    for key in REQUIRED:
        if key not in rows:
            found.append(f"missing string {key}")
    for key, row in rows.items():
        if not key.startswith(PRICE_SCANNED):
            continue
        for price in FORBIDDEN:
            if price in row:
                found.append(f"{key} hard-codes {price}")
    for name, source in (sources or {}).items():
        for price in FORBIDDEN:
            if price in source:
                found.append(f"{name} hard-codes {price}")
    return found


def self_test() -> int:
    sample = {
        "products": [
            {
                "id": "orehruoy.sewlens.credit",
                "type": "consumable",
                "listings": {"en": {"name": "A" * 31, "description": "ok"}},
            }
        ]
    }
    small = b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\x0dIHDR" + (390).to_bytes(4, "big") + (844).to_bytes(4, "big") + b"x" * 1000
    bad = problems(sample, small, "pay_credit,ok\npay_legal,only $2.99\n", {"paywall": "label.text = \"24,99 €\""})
    expected = ("name length", "pay_legal hard-codes", "paywall hard-codes", "below 640x920")
    missing = [text for text in expected if not any(text in item for item in bad)]
    if missing:
        print(f"self-test failed to catch: {missing}", file=sys.stderr)
        return 1
    print("check_iap_listings self-test OK")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    listings = json.loads(LISTINGS.read_text(encoding="utf-8"))
    review = REVIEW.read_bytes() if REVIEW.is_file() else b""
    found = problems(listings, review, STRINGS.read_text(encoding="utf-8"), {PAYWALL.name: PAYWALL.read_text(encoding="utf-8")})
    if found:
        print("\n".join(found), file=sys.stderr)
        return 1
    print("IAP listings OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
