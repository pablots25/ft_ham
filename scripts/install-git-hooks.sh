#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -d "${repo_root}/.git" ]]; then
  echo "Not a git repository: ${repo_root}"
  exit 1
fi

chmod +x "${repo_root}/.githooks/pre-push"
git -C "${repo_root}" config core.hooksPath .githooks

echo "✅ Git hooks installed"
echo "hooksPath: $(git -C "${repo_root}" config --get core.hooksPath)"
