#!/usr/bin/env bash
# scripts/bump_version.sh
# Sets MARKETING_VERSION and CURRENT_PROJECT_VERSION in ft8_ham.xcodeproj.
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

if [[ ! -f "$XCODEPROJ" ]]; then
  echo "Error: project.pbxproj not found at $XCODEPROJ"
  exit 1
fi

echo "Bumping version to $MARKETING_VERSION (build $BUILD_NUMBER) in $XCODEPROJ"

# Use agvtool to set the marketing version (CFBundleShortVersionString)
# agvtool works from the directory that contains the .xcodeproj
cd "$PROJECT_ROOT"
xcrun agvtool new-marketing-version "$MARKETING_VERSION"
xcrun agvtool new-version -all "$BUILD_NUMBER"

echo "Done. Versions set:"
echo "  MARKETING_VERSION         = $MARKETING_VERSION"
echo "  CURRENT_PROJECT_VERSION   = $BUILD_NUMBER"
