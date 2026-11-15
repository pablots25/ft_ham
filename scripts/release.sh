#!/usr/bin/env bash
# scripts/release.sh
# Archives a release build in a throwaway worktree and uploads it to App Store Connect.
#
# ft8_ham.xcodeproj, Assets.xcassets and GoogleService-Info.plist are not in git,
# so they are copied from a full local checkout into the worktree. The checkout
# you work in is never switched or modified. See docs/RELEASING.md.
#
# Usage:
#   scripts/release.sh <version> <build> [options]
#
# Options:
#   --ref <git-ref>          Commit to build (default: HEAD)
#   --premium-ref <git-ref>  ft_ham_premium commit to build against (default: main)
#   --inputs <dir>           Checkout holding the ignored inputs (default: this repo, else ../ft_ham)
#   --export-only            Skip the archive and upload the existing archive for this version and build
#   --no-upload              Archive only, do not upload
#   --skip-benchmark         Do not run scripts/benchmark.sh before archiving
#   --dry-run                Print every step without running it
#
# Example:
#   scripts/release.sh 1.3.2 28 --ref hotfix/1.3.2 --premium-ref hotfix/1.3.2 --dry-run

set -euo pipefail

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

VERSION="${1:-}"
BUILD="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || usage
shift 2

REF="HEAD"
PREMIUM_REF="main"
INPUTS=""
EXPORT_ONLY=false
UPLOAD=true
BENCHMARK=true
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --premium-ref) PREMIUM_REF="$2"; shift 2 ;;
    --inputs) INPUTS="$2"; shift 2 ;;
    --export-only) EXPORT_ONLY=true; shift ;;
    --no-upload) UPLOAD=false; shift ;;
    --skip-benchmark) BENCHMARK=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) usage ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PARENT="$(dirname "$REPO")"
PREMIUM="$PARENT/ft_ham_premium"
WORKTREE="$PARENT/ft_ham-release-b$BUILD"
ARCHIVE_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ARCHIVE="$ARCHIVE_DIR/ft8_ham-$VERSION-$BUILD.xcarchive"
IGNORED_INPUTS=(ft8_ham.xcodeproj ft8_ham/Assets.xcassets ft8_ham/GoogleService-Info.plist)
OPTIONAL_INPUTS=(Configuration.storekit)

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
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

# ── 1. Preflight ─────────────────────────────────────────────────────────────
step "Preflight for FT Ham $VERSION ($BUILD) from $REF"

SHA="$(git -C "$REPO" rev-parse --verify "$REF^{commit}")" || fail "unknown ref $REF"
echo "Commit: $SHA"

if file_version="$(git -C "$REPO" show "$SHA:VERSION" 2>/dev/null)"; then
  file_version="$(echo "$file_version" | tr -d '[:space:]')"
  [[ "$file_version" == "$VERSION" ]] \
    || fail "VERSION at $REF is $file_version. Run scripts/bump_version.sh $VERSION $BUILD and commit first."
else
  echo "Warning: $REF has no VERSION file. The Release workflow will reject the tag until it has one."
fi

notes="$(mktemp -t ftham-notes)"
trap 'rm -f "$notes"' EXIT
if git -C "$REPO" show "$SHA:.github/RELEASE_NOTES.md" > "$notes" 2>/dev/null; then
  python3 -I "$SCRIPT_DIR/check_release_notes.py" "$VERSION" --file "$notes" \
    || fail "release notes at $REF need fixing first"
else
  echo "Warning: $REF has no .github/RELEASE_NOTES.md. Run scripts/release_notes.sh $VERSION."
fi

if [[ -z "$INPUTS" ]]; then
  if [[ -d "$REPO/ft8_ham.xcodeproj" ]]; then INPUTS="$REPO"; else INPUTS="$PARENT/ft_ham"; fi
fi
if ! $EXPORT_ONLY; then
  for input in "${IGNORED_INPUTS[@]}"; do
    [[ -e "$INPUTS/$input" ]] || fail "$INPUTS/$input is missing. Pass --inputs <checkout>."
  done
  echo "Ignored inputs from: $INPUTS"
fi

[[ -d "$PREMIUM/.git" || -f "$PREMIUM/.git" ]] || fail "ft_ham_premium not found at $PREMIUM"
PREMIUM_SHA="$(git -C "$PREMIUM" rev-parse --verify "$PREMIUM_REF^{commit}")" || fail "unknown premium ref $PREMIUM_REF"
echo "Premium: $PREMIUM_REF ($PREMIUM_SHA)"

if ! $EXPORT_ONLY; then
  # ── 2. Worktree ────────────────────────────────────────────────────────────
  step "Worktree $WORKTREE"
  if [[ -e "$WORKTREE" ]]; then
    confirm "$WORKTREE already exists. Reuse it and check out $SHA there?" || fail "stopped"
    run git -C "$WORKTREE" checkout --detach "$SHA"
  else
    run git -C "$REPO" worktree add --detach "$WORKTREE" "$SHA"
  fi

  step "Copy the ignored inputs"
  for input in "${IGNORED_INPUTS[@]}" "${OPTIONAL_INPUTS[@]}"; do
    [[ -e "$INPUTS/$input" ]] || continue
    if [[ -d "$INPUTS/$input" ]]; then
      run rsync -a --delete --exclude xcuserdata "$INPUTS/$input/" "$WORKTREE/$input/"
    else
      run rsync -a "$INPUTS/$input" "$WORKTREE/$input"
    fi
  done

  # ── 3. Premium package ─────────────────────────────────────────────────────
  step "Premium package"
  premium_head="$(git -C "$PREMIUM" rev-parse HEAD)"
  premium_dirty="$(git -C "$PREMIUM" status --porcelain --untracked-files=no)"
  if [[ "$premium_head" == "$PREMIUM_SHA" && -z "$premium_dirty" ]]; then
    echo "$PREMIUM is clean at $PREMIUM_REF, building against it."
  else
    premium_tree="$PARENT/ft_ham_premium-release-b$BUILD"
    echo "$PREMIUM is on $(git -C "$PREMIUM" branch --show-current || echo detached) at ${premium_head:0:7}${premium_dirty:+ with local changes}."
    echo "Building against a detached premium worktree at $premium_tree instead."
    if [[ -e "$premium_tree" ]]; then
      run git -C "$premium_tree" checkout --detach "$PREMIUM_SHA"
    else
      run git -C "$PREMIUM" worktree add --detach "$premium_tree" "$PREMIUM_SHA"
    fi
    relative="../$(basename "$premium_tree")"
    run sed -i '' "s#relativePath = \.\./ft_ham_premium[^;]*;#relativePath = $relative;#" \
      "$WORKTREE/ft8_ham.xcodeproj/project.pbxproj"
  fi

  # ── 4. Version and build number ────────────────────────────────────────────
  step "Set version $VERSION and build $BUILD"
  run env PROJECT_ROOT="$WORKTREE" bash "$SCRIPT_DIR/bump_version.sh" "$VERSION" "$BUILD"

  # ── 5. Benchmarks ──────────────────────────────────────────────────────────
  # Decode and message-processing benchmarks on the release commit, compared
  # with the previous release measured on this Mac. See docs/RELEASING.md.
  if $BENCHMARK; then
    step "Benchmarks"
    if $DRY_RUN; then
      printf '+ %s\n' "bash $SCRIPT_DIR/benchmark.sh $VERSION $BUILD --project-root $WORKTREE"
    else
      bench_status=0
      bash "$SCRIPT_DIR/benchmark.sh" "$VERSION" "$BUILD" --project-root "$WORKTREE" || bench_status=$?
      case $bench_status in
        0) ;;
        2) confirm "Benchmarks regressed against the previous release. Archive anyway?" \
             || fail "stopped on a performance regression. Profile it, or rerun with --skip-benchmark." ;;
        *) fail "benchmarks could not run. Fix them, or rerun with --skip-benchmark." ;;
      esac
    fi
  else
    echo "Benchmarks skipped (--skip-benchmark)."
  fi

  # ── 6. Archive ─────────────────────────────────────────────────────────────
  step "Archive"
  run mkdir -p "$ARCHIVE_DIR"
  run xcodebuild archive \
    -project "$WORKTREE/ft8_ham.xcodeproj" \
    -scheme ft8_ham \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates
else
  if [[ ! -d "$ARCHIVE" ]]; then
    found="$(ls -d "$HOME"/Library/Developer/Xcode/Archives/*/"ft8_ham-$VERSION-$BUILD.xcarchive" 2>/dev/null | tail -n 1 || true)"
    [[ -n "$found" ]] || fail "no archive ft8_ham-$VERSION-$BUILD.xcarchive found"
    ARCHIVE="$found"
  fi
  echo "Using $ARCHIVE"
fi

# ── 7. dSYMs ─────────────────────────────────────────────────────────────────
step "Zip dSYMs"
DSYM_ZIP="$(dirname "$ARCHIVE")/ft8_ham-$VERSION-$BUILD-dSYMs.zip"
run ditto -c -k --keepParent "$ARCHIVE/dSYMs" "$DSYM_ZIP"

# ── 8. Upload ────────────────────────────────────────────────────────────────
if $UPLOAD; then
  step "Upload to App Store Connect"
  team="$(sed -n 's/.*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/p' \
    "${WORKTREE}/ft8_ham.xcodeproj/project.pbxproj" "$INPUTS/ft8_ham.xcodeproj/project.pbxproj" 2>/dev/null | head -n 1 || true)"
  [[ -n "$team" ]] || $DRY_RUN || fail "could not read DEVELOPMENT_TEAM from the project"
  export_dir="$(mktemp -d -t ftham-export)"
  cat > "$export_dir/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>${team}</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
  if confirm "Upload FT Ham $VERSION ($BUILD) to App Store Connect?"; then
    if ! run xcodebuild -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportOptionsPlist "$export_dir/ExportOptions.plist" \
      -exportPath "$export_dir" \
      -allowProvisioningUpdates; then
      echo
      echo "Upload failed. Common causes:"
      echo "  * 'Failed to Use Accounts': sign in again in Xcode Settings, Accounts, then rerun with --export-only"
      echo "  * 'bundle version must be higher' or 'Redundant Binary Upload': App Store Connect already has build $BUILD, rerun with a higher build"
      exit 1
    fi
  else
    echo "Upload skipped."
  fi
fi

step "Done"
echo "Archive: $ARCHIVE"
echo "dSYMs:   $DSYM_ZIP"
echo
echo "Next: smoke test on TestFlight, submit for review, merge into main and develop,"
echo "then tag both repositories with: scripts/tag_release.sh $VERSION --premium-ref $PREMIUM_SHA"
echo "Remember to bump CURRENT_PROJECT_VERSION in your own checkout to $BUILD as well."
if $BENCHMARK && ! $EXPORT_ONLY && [[ -f "$REPO/benchmarks/$VERSION-$BUILD.json" ]]; then
  echo "Commit benchmarks/$VERSION-$BUILD.json on the release branch so the next release compares against it."
fi
