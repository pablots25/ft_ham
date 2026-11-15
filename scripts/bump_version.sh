#!/usr/bin/env bash
# scripts/bump_version.sh
# Sets the marketing version and build number.
#   * VERSION (tracked, read by the Release workflow) gets the marketing version.
#   * ft8_ham.xcodeproj (not tracked) gets MARKETING_VERSION and CURRENT_PROJECT_VERSION
#     when it is present. Debug configurations keep their "-debug" suffix.
#
# Usage:
#   ./scripts/bump_version.sh <marketing_version> <build_number>
#
# Example (from GitHub Actions):
#   ./scripts/bump_version.sh 1.3.0 ${{ github.run_number }}
#
# Environment:
#   PROJECT_ROOT — optional override; defaults to the directory one level above
#                  this script (i.e. the repo root).

set -euo pipefail

MARKETING_VERSION="${1:-}"
BUILD_NUMBER="${2:-}"

if [[ -z "$MARKETING_VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "Usage: $0 <marketing_version> <build_number>"
  exit 1
fi

# Validate semver-ish (digits and dots only for the core version)
if ! [[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: MARKETING_VERSION must be in X.Y.Z format (got: '$MARKETING_VERSION')"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-"$(dirname "$SCRIPT_DIR")"}"
XCODEPROJ="$PROJECT_ROOT/ft8_ham.xcodeproj/project.pbxproj"

printf '%s\n' "$MARKETING_VERSION" > "$PROJECT_ROOT/VERSION"
echo "VERSION set to $MARKETING_VERSION"

if [[ ! -f "$XCODEPROJ" ]]; then
  echo "No Xcode project at $XCODEPROJ (it is not in git). Only VERSION was updated."
  exit 0
fi

echo "Bumping version to $MARKETING_VERSION (build $BUILD_NUMBER) in $XCODEPROJ"

# Release configurations use a bare version, Debug ones "X.Y.Z-debug".
# agvtool new-marketing-version would overwrite both, so edit the project directly.
sed -i '' -E \
  -e "s/MARKETING_VERSION = \"[0-9]+\\.[0-9]+\\.[0-9]+-debug\";/MARKETING_VERSION = \"$MARKETING_VERSION-debug\";/" \
  -e "s/MARKETING_VERSION = [0-9]+\\.[0-9]+\\.[0-9]+;/MARKETING_VERSION = $MARKETING_VERSION;/" \
  "$XCODEPROJ"

# agvtool works from the directory that contains the .xcodeproj
cd "$PROJECT_ROOT"
xcrun agvtool new-version -all "$BUILD_NUMBER"

echo "Done. Versions set:"
echo "  MARKETING_VERSION         = $MARKETING_VERSION (Debug: $MARKETING_VERSION-debug)"
echo "  CURRENT_PROJECT_VERSION   = $BUILD_NUMBER"
