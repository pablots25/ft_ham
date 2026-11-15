#!/usr/bin/env python3
"""Checks .github/RELEASE_NOTES.md against the release notes style rules.

Usage:
    python3 scripts/check_release_notes.py [version] [--file PATH] [--allow-missing]

Rules (docs/RELEASING.md):
  * the first heading names the version ("# FT Ham 1.3.2")
  * no em dashes, en dashes used as dashes, or semicolons
  * no leftover TODO placeholders or {{TEMPLATE}} markers
  * a Full Changelog link is present

Exit codes: 0 ok, 1 style errors, 2 file missing (unless --allow-missing),
3 with --names-version when the file is missing or names another version.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_FILE = ROOT / ".github" / "RELEASE_NOTES.md"


def check(text: str, version: str | None) -> list[str]:
    errors: list[str] = []
    lines = text.splitlines()

    heading = first_heading(text)
    if heading is None:
        errors.append("missing a top level '# FT Ham X.Y.Z' heading")
    elif version and not re.search(rf"(?<![\d.]){re.escape(version)}(?![\d.])", heading):
        errors.append(f"first heading '{heading}' does not name version {version}")

    in_code = False
    for number, line in enumerate(lines, start=1):
        if line.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        # Links and inline code may hold anything.
        prose = re.sub(r"`[^`]*`|\]\([^)]*\)|https?://\S+", "", line)
        if "—" in prose:
            errors.append(f"line {number}: em dash, rewrite as two sentences or use a comma")
        if re.search(r"\s–\s", prose):
            errors.append(f"line {number}: en dash used as a dash")
        if ";" in prose:
            errors.append(f"line {number}: semicolon, split the sentence")
        if re.search(r"\bTODO\b", prose):
            errors.append(f"line {number}: TODO placeholder left in the notes")
        if "{{" in prose or "}}" in prose:
            errors.append(f"line {number}: unfilled template marker")

    if "Full Changelog" not in text:
        errors.append("missing the 'Full Changelog' compare link")
    return errors


def first_heading(text: str) -> str | None:
    return next((line for line in text.splitlines() if line.startswith("# ")), None)


def names_version(path: Path, version: str) -> bool:
    if not path.exists():
        return False
    heading = first_heading(path.read_text(encoding="utf-8"))
    return heading is not None and re.search(rf"(?<![\d.]){re.escape(version)}(?![\d.])", heading) is not None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("version", nargs="?", help="expected version, e.g. 1.3.2")
    parser.add_argument("--file", type=Path, default=DEFAULT_FILE)
    parser.add_argument("--allow-missing", action="store_true",
                        help="exit 0 when the notes file does not exist")
    parser.add_argument("--names-version", action="store_true",
                        help="only report whether the file exists and its first heading names the version (exit 0 or 3)")
    args = parser.parse_args()

    if args.names_version:
        if not args.version:
            parser.error("--names-version needs a version")
        return 0 if names_version(args.file, args.version) else 3

    if not args.file.exists():
        if args.allow_missing:
            print(f"{args.file.name} not present, nothing to check.")
            return 0
        print(f"error: {args.file} not found. Run scripts/release_notes.sh first.", file=sys.stderr)
        return 2

    errors = check(args.file.read_text(encoding="utf-8"), args.version)
    for error in errors:
        print(f"::error file={args.file.relative_to(ROOT) if args.file.is_relative_to(ROOT) else args.file}::{error}")
    if errors:
        print(f"{len(errors)} release notes problem(s).", file=sys.stderr)
        return 1
    print("Release notes look good.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
