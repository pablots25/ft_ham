#!/usr/bin/env python3
"""Fails when the main app imports FTHamPremium outside an #if canImport(FTHamPremium) block.

The public repository must build without the private premium package (AGENTS.md,
"Premium Package Architecture"). Usage: python3 scripts/check_premium_guard.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIRS = ["ft8_ham", "ft8_hamTests", "ft8_hamUITests"]
IMPORT = re.compile(r"^\s*(@\w+(\(.*\))?\s+)*import\s+FTHamPremium\b")
GUARD = re.compile(r"canImport\(\s*FTHamPremium\s*\)")


def unguarded_imports(path: Path) -> list[int]:
    stack: list[bool] = []  # one entry per open #if, True when it guards FTHamPremium
    problems: list[int] = []
    for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append(bool(GUARD.search(stripped)) and "!" not in stripped.split("canImport")[0])
        elif stripped.startswith("#elseif") or stripped.startswith("#else"):
            if stack:
                stack[-1] = bool(GUARD.search(stripped)) if stripped.startswith("#elseif") else False
        elif stripped.startswith("#endif"):
            if stack:
                stack.pop()
        elif IMPORT.match(line) and not any(stack):
            problems.append(number)
    return problems


def main() -> int:
    failed = False
    for directory in SOURCE_DIRS:
        base = ROOT / directory
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.swift")):
            for number in unguarded_imports(path):
                print(f"::error file={path.relative_to(ROOT)},line={number}::"
                      "import FTHamPremium must sit inside #if canImport(FTHamPremium)")
                failed = True
    if not failed:
        print("All FTHamPremium imports are guarded.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
