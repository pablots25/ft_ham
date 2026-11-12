#!/usr/bin/env python3
"""Validates the String Catalogs (.xcstrings) shipped with the app.

Usage:
    python3 scripts/check_strings.py [--strict]

Checks every tracked *.xcstrings under ft8_ham/:
  * the file is valid JSON with a "strings" object
  * every translatable key has a translation for each language the catalog uses
  * no translation is still in the "new" or "needs_review" state

Without --strict, problems are reported as GitHub warnings and the exit code is 0,
so pull requests are not blocked. With --strict (release tags), they fail the run.
Invalid JSON always fails.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNFINISHED_STATES = {"new", "needs_review"}
FORMAT_SPECIFIER = re.compile(r"%(\d+\$)?[-+ #0]*\d*(\.\d+)?(ll|l|h|q|z|t|j)?[@dDuUxXoOfeEgGcCsSpaAi%]")
MAX_LISTED = 15


def needs_translation(key: str) -> bool:
    """Keys made only of numbers, symbols and format specifiers ("0/30", "%lld dB") read the same in every language."""
    words = FORMAT_SPECIFIER.sub("", key)
    return re.search(r"[^\W\d_]{2,}", words) is not None


def catalog_problems(path: Path) -> tuple[list[str], list[str]]:
    """Returns (fatal, warnings) for one catalog."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return [f"invalid JSON: {error}"], []
    strings = data.get("strings")
    if not isinstance(strings, dict):
        return ["no 'strings' object"], []

    source = data.get("sourceLanguage", "en")
    languages = sorted({
        language
        for entry in strings.values()
        for language in entry.get("localizations", {})
        if language != source
    })

    warnings: list[str] = []
    for key, entry in sorted(strings.items()):
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        if not needs_translation(key):
            continue
        localizations = entry.get("localizations", {})
        missing = [language for language in languages if language not in localizations]
        if missing:
            warnings.append(f"'{key}' has no {', '.join(missing)} translation")
        for language, value in localizations.items():
            state = value.get("stringUnit", {}).get("state")
            if state in UNFINISHED_STATES:
                warnings.append(f"'{key}' [{language}] is still '{state}'")
    return [], warnings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--strict", action="store_true", help="fail on missing or unfinished translations")
    args = parser.parse_args()

    catalogs = sorted((ROOT / "ft8_ham").rglob("*.xcstrings"))
    if not catalogs:
        print("::error::no .xcstrings files found under ft8_ham/")
        return 1

    level = "error" if args.strict else "warning"
    failed = False
    for catalog in catalogs:
        relative = catalog.relative_to(ROOT)
        fatal, warnings = catalog_problems(catalog)
        for problem in fatal:
            print(f"::error file={relative}::{problem}")
            failed = True
        for problem in warnings[:MAX_LISTED]:
            print(f"::{level} file={relative}::{problem}")
        if len(warnings) > MAX_LISTED:
            print(f"::{level} file={relative}::and {len(warnings) - MAX_LISTED} more")
        if warnings and args.strict:
            failed = True
        print(f"{relative}: {len(warnings)} translation problem(s)")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
