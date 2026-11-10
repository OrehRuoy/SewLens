"""Sewing-guide strings use the glossary terms, in every language.

   python3 tools/check_glossary.py
   python3 tools/check_glossary.py --self-test
"""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GLOSSARY = ROOT / "i18n" / "glossary.csv"
STRINGS = ROOT / "i18n" / "strings.csv"
GUIDES = ROOT / "data" / "guides"
DESIGNS = ROOT / "data" / "designs.json"
RULES = ROOT / "data" / "fit_feedback.json"
RULES_FUNCTIONS = ROOT / "functions" / "src" / "fit-feedback.json"
LOCALES = ["en", "de", "fr", "es", "pt_BR", "ja", "it", "nl"]
# Sewing instructions only. Body-measurement copy is not a pattern term.
CHECKED_PREFIXES = ("guide_",)
CHECKED_KEYS = {"draft_print_tip"}
SEAM_ALLOWANCE = {
    "en": "seam allowance",
    "de": "Nahtzugabe",
    "fr": "valeur de couture",
    "es": "margen de costura",
    "pt_BR": "margem de costura",
    "ja": "縫い代",
    "it": "margine di cucitura",
    "nl": "naadtoeslag",
}


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def glossary_terms():
    terms = []
    for row in read_csv(GLOSSARY):
        item = {"key": row["key"]}
        for locale in LOCALES:
            column = "pt-BR" if locale == "pt_BR" else locale
            item[locale] = row[column].strip()
        terms.append(item)
    terms.sort(key=lambda item: len(item["en"]), reverse=True)
    return terms


def phrases_in(text, terms):
    work = text.casefold()
    found = []
    for term in terms:
        phrase = term["en"].casefold()
        if phrase and phrase in work:
            found.append(term)
            work = work.replace(phrase, " " * len(phrase))
    return found


def string_problems(rows, terms):
    problems = []
    by_key = {row["keys"]: row for row in rows if row.get("keys")}
    for key, row in by_key.items():
        if not (key.startswith(CHECKED_PREFIXES) or key in CHECKED_KEYS):
            continue
        english = row.get("en", "")
        for term in phrases_in(english, terms):
            for locale in LOCALES:
                if locale == "en" or locale not in term:
                    continue
                if term[locale].casefold() not in row.get(locale, "").casefold():
                    problems.append(f"{key} {locale} is missing glossary {term['key']} ({term[locale]})")
    return problems


def guide_problems(rows):
    problems = []
    by_key = {row["keys"]: row for row in rows if row.get("keys")}
    designs = json.loads(DESIGNS.read_text(encoding="utf-8"))["designs"]
    for name in designs:
        path = GUIDES / f"{name}.json"
        if not path.exists():
            problems.append(f"missing guide for {name}")
            continue
        guide = json.loads(path.read_text(encoding="utf-8"))
        keys = list(guide.get("steps") or []) + list(guide.get("notes") or [])
        if not guide.get("steps"):
            problems.append(f"{name} has no steps")
        if guide.get("notes") != [f"guide_note_{name}"]:
            problems.append(f"{name} note key must be guide_note_{name}")
        for key in keys:
            row = by_key.get(key)
            if row is None:
                problems.append(f"{name} uses missing string {key}")
                continue
            for locale in LOCALES:
                if not str(row.get(locale, "")).strip():
                    problems.append(f"{key} has no {locale} text")
    return problems


def rule_problems(rows):
    problems = []
    client = json.loads(RULES.read_text(encoding="utf-8"))
    server = json.loads(RULES_FUNCTIONS.read_text(encoding="utf-8"))
    if client != server:
        problems.append("data/fit_feedback.json does not match functions/src/fit-feedback.json")
    by_key = {row["keys"]: row for row in rows if row.get("keys")}
    for item in client.get("complaints", []):
        key = "fit_" + item["id"]
        row = by_key.get(key)
        if row is None:
            problems.append(f"missing string {key}")
            continue
        for locale in LOCALES:
            if not str(row.get(locale, "")).strip():
                problems.append(f"{key} has no {locale} text")
    return problems


def seam_allowance_problem(terms):
    found = next((term for term in terms if term["key"] == "seam_allowance"), None)
    if found is None:
        return ["glossary is missing seam_allowance"]
    problems = []
    for locale, expected in SEAM_ALLOWANCE.items():
        if found[locale] != expected:
            problems.append(f"seam_allowance {locale} is {found[locale]!r}, expected {expected!r}")
    return problems


def collect():
    terms = glossary_terms()
    rows = read_csv(STRINGS)
    return seam_allowance_problem(terms) + string_problems(rows, terms) + guide_problems(rows) + rule_problems(rows)


def self_test():
    terms = [
        {"key": "seam_allowance", "en": "seam allowance", "de": "Nahtzugabe"},
        {"key": "seam", "en": "seam", "de": "Naht"},
    ]
    rows = [
        {"keys": "guide_ok", "en": "The seam allowance is included.", "de": "Die Nahtzugabe ist enthalten."},
        {"keys": "guide_bad", "en": "Press the seam.", "de": "Bügle die Kante."},
        {"keys": "how_chest", "en": "The seam is on the body.", "de": "Keine Naht hier."},
    ]
    found = string_problems(rows, terms)
    if found != ["guide_bad de is missing glossary seam (Naht)"]:
        print("self-test failed:", found)
        return 1
    print("check_glossary.py self-test passed")
    return 0


def main(argv):
    if "--self-test" in argv:
        return self_test()
    problems = collect()
    if problems:
        print("\n".join(problems))
        return 1
    print("glossary, guides, and fit strings are consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
