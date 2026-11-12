#!/usr/bin/env bash
# scripts/release_notes.sh
# Drafts .github/RELEASE_NOTES.md from the Conventional Commits since the last tag.
# The draft is a starting point: rewrite it by hand before tagging (docs/RELEASING.md).
#
# Usage:
#   scripts/release_notes.sh <version> [previous_tag] [--stdout]
#
# Examples:
#   scripts/release_notes.sh 1.3.2
#   scripts/release_notes.sh 1.3.2 1.3.1 --stdout

set -euo pipefail

VERSION="${1:-}"
PREVIOUS="${2:-}"
TO_STDOUT=false
for arg in "$@"; do
  [[ "$arg" == "--stdout" ]] && TO_STDOUT=true
done
[[ "$PREVIOUS" == "--stdout" ]] && PREVIOUS=""

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <X.Y.Z> [previous_tag] [--stdout]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/.github/RELEASE_NOTES.template.md"
OUTPUT="$ROOT/.github/RELEASE_NOTES.md"

if [[ -z "$PREVIOUS" ]]; then
  # Latest X.Y.Z tag reachable from HEAD that is not the version being drafted.
  PREVIOUS="$(git -C "$ROOT" tag --merged HEAD --sort=-v:refname \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | grep -vx "$VERSION" | head -n 1 || true)"
fi
if [[ -z "$PREVIOUS" ]]; then
  echo "Error: no previous X.Y.Z tag found. Pass it as the second argument." >&2
  exit 1
fi

new="" improved="" fixed="" other=""
while IFS= read -r subject; do
  [[ -z "$subject" ]] && continue
  # type(scope)!: description
  if [[ "$subject" =~ ^([a-z]+)(\(([^\)]*)\))?(!)?:[[:space:]]*(.*)$ ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]}"
    desc="${BASH_REMATCH[5]}"
  else
    type="other" scope="" desc="$subject"
  fi
  # Capitalize the first letter for the draft.
  first="$(printf '%s' "${desc:0:1}" | tr '[:lower:]' '[:upper:]')"
  line="* ${first}${desc:1}"
  [[ -n "$scope" ]] && line="$line ($scope)"
  case "$type" in
    feat) new+="$line"$'\n' ;;
    perf|refactor|style|a11y) improved+="$line"$'\n' ;;
    fix) fixed+="$line"$'\n' ;;
    chore|ci|build|docs|test|release) ;; # not operator facing
    *) other+="$line"$'\n' ;;
  esac
done < <(git -C "$ROOT" log --no-merges --reverse --format='%s' "${PREVIOUS}..HEAD")

sections=""
[[ -n "$new" ]] && sections+=$'## New\n\n'"$new"$'\n'
[[ -n "$improved" ]] && sections+=$'## Improved\n\n'"$improved"$'\n'
[[ -n "$fixed" ]] && sections+=$'## Fixed\n\n'"$fixed"$'\n'
[[ -n "$other" ]] && sections+=$'## TODO: sort these\n\n'"$other"$'\n'
[[ -z "$sections" ]] && sections=$'TODO: no operator facing commits found.\n'
while [[ "$sections" == *$'\n' ]]; do sections="${sections%$'\n'}"; done

draft="$(cat "$TEMPLATE")"
draft="${draft//\{\{VERSION\}\}/$VERSION}"
draft="${draft//\{\{PREVIOUS\}\}/$PREVIOUS}"
draft="${draft//\{\{SECTIONS\}\}/$sections}"

if $TO_STDOUT; then
  printf '%s\n' "$draft"
else
  printf '%s\n' "$draft" > "$OUTPUT"
  echo "Draft written to ${OUTPUT#"$ROOT"/} (${PREVIOUS}..HEAD)."
  echo "Rewrite it for operators, then run: python3 scripts/check_release_notes.py $VERSION"
fi
