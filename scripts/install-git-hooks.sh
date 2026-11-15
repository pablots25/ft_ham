#!/usr/bin/env bash
# Installs the repo-managed hooks in .githooks for this clone, every worktree
# and the sibling ft_ham_premium clone.
#
#   pre-push    blocks pushes of premium/private paths (app repo only)
#   commit-msg  gitflow guard: merges only on main/develop, merges and
#               "chore(release): ..." commits on release/* and hotfix/*
#
# core.hooksPath is set to an absolute path so worktrees on branches that
# predate a hook still run it. Run this from the main checkout.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hooks_dir="${repo_root}/.githooks"

if ! git -C "${repo_root}" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not a git repository: ${repo_root}"
  exit 1
fi

chmod +x "${hooks_dir}/pre-push" "${hooks_dir}/commit-msg"
git -C "${repo_root}" config core.hooksPath "${hooks_dir}"

echo "✅ Git hooks installed"
echo "hooksPath: $(git -C "${repo_root}" config --get core.hooksPath)"

# Premium shares the branch names, so it gets the same gitflow guard (but not
# pre-push, whose path rules are for the public app repo).
premium_root="$(cd "${repo_root}/.." && pwd)/ft_ham_premium"
if premium_git="$(git -C "${premium_root}" rev-parse --git-common-dir 2>/dev/null)"; then
  [[ "${premium_git}" = /* ]] || premium_git="${premium_root}/${premium_git}"
  mkdir -p "${premium_git}/hooks"
  ln -sf "${hooks_dir}/commit-msg" "${premium_git}/hooks/commit-msg"
  echo "✅ Premium commit-msg hook linked in ${premium_git}/hooks"
fi
