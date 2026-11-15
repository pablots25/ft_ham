#!/usr/bin/env bash
# scripts/tag_release.sh
# Tags a shipped version in ft_ham and ft_ham_premium, then pushes the tags.
# Pushing the app tag starts .github/workflows/release.yml, which creates the
# GitHub Release from .github/RELEASE_NOTES.md. See docs/RELEASING.md.
#
# Usage:
#   scripts/tag_release.sh <version> [--ref <git-ref>] [--premium-ref <git-ref>] [--dry-run]
#
#   --ref          App commit to tag (default: main)
#   --premium-ref  Premium commit that was built (default: main of ft_ham_premium)
#   --dry-run      Run every check and print the commands without tagging or pushing

set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
shift

REF="main"
PREMIUM_REF="main"
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --premium-ref) PREMIUM_REF="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) usage ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PREMIUM="$(dirname "$REPO")/ft_ham_premium"

run() {
  printf '+ %s\n' "$*"
  if ! $DRY_RUN; then "$@"; fi
}
confirm() {
  if $DRY_RUN; then echo "(dry run) would ask: $1"; return 0; fi
  local answer
  read -r -p "$1 [y/N] " answer
  [[ "$answer" == y || "$answer" == Y || "$answer" == yes ]]
}
fail() { echo "Error: $*" >&2; exit 1; }

run git -C "$REPO" fetch --tags origin
run git -C "$PREMIUM" fetch --tags origin

SHA="$(git -C "$REPO" rev-parse --verify "$REF^{commit}")" || fail "unknown ref $REF"
PREMIUM_SHA="$(git -C "$PREMIUM" rev-parse --verify "$PREMIUM_REF^{commit}")" || fail "unknown premium ref $PREMIUM_REF"

git -C "$REPO" rev-parse -q --verify "refs/tags/$VERSION" > /dev/null && fail "tag $VERSION already exists in ft_ham"
git -C "$PREMIUM" rev-parse -q --verify "refs/tags/$VERSION" > /dev/null && fail "tag $VERSION already exists in ft_ham_premium"

file_version="$(git -C "$REPO" show "$SHA:VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
[[ "$file_version" == "$VERSION" ]] || fail "VERSION at $REF is '${file_version:-missing}', expected $VERSION"

notes="$(mktemp -t ftham-notes)"
trap 'rm -f "$notes"' EXIT
if git -C "$REPO" show "$SHA:.github/RELEASE_NOTES.md" > "$notes" 2>/dev/null; then
  python3 -I "$SCRIPT_DIR/check_release_notes.py" "$VERSION" --file "$notes" || fail "release notes need fixing first"
else
  echo "Warning: no .github/RELEASE_NOTES.md at $REF. The GitHub Release will use the generated commit list."
fi

echo
echo "ft_ham          $VERSION -> ${SHA:0:7}  $(git -C "$REPO" log -1 --format=%s "$SHA")"
echo "ft_ham_premium  $VERSION -> ${PREMIUM_SHA:0:7}  $(git -C "$PREMIUM" log -1 --format=%s "$PREMIUM_SHA")"
echo

confirm "Create both annotated tags?" || fail "stopped"
run git -C "$REPO" tag -a "$VERSION" -m "Version $VERSION" "$SHA"
run git -C "$PREMIUM" tag -a "$VERSION" -m "Version $VERSION" "$PREMIUM_SHA"

if confirm "Push both tags to origin? This starts the Release workflow and publishes the GitHub Release."; then
  run git -C "$PREMIUM" push origin "refs/tags/$VERSION"
  run git -C "$REPO" push origin "refs/tags/$VERSION"
  echo "Pushed. Follow the run with: gh run watch --repo pablots25/ft_ham"
else
  echo "Tags created locally only. Push later with:"
  echo "  git -C $PREMIUM push origin refs/tags/$VERSION"
  echo "  git -C $REPO push origin refs/tags/$VERSION"
fi
