"""Unit tests for .githooks/commit-msg, the gitflow guard (offline, temporary repos).

Run with: python3 -m unittest discover -s scripts/tests -v
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

HOOKS_DIR = Path(__file__).resolve().parents[2] / ".githooks"


class CommitMsgHookTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        self.git("config", "core.hooksPath", str(HOOKS_DIR))
        self.git("commit", "-q", "--allow-empty", "--no-verify", "-m", "init")
        self.git("branch", "develop")
        self.git("branch", "release/1.0.0")
        self.git("branch", "hotfix/1.0.1")

    def tearDown(self):
        self._tmp.cleanup()

    def git(self, *args, check=True):
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        return subprocess.run(
            ["git", *args], cwd=self.repo, env=env, check=check,
            capture_output=True, text=True,
        )

    def commit(self, message):
        return self.git("commit", "-q", "--allow-empty", "-m", message, check=False).returncode == 0

    def test_main_and_develop_block_direct_commits(self):
        for branch in ("main", "develop"):
            self.git("switch", "-q", branch)
            self.assertFalse(self.commit("fix: direct"), branch)
            self.assertFalse(self.commit("chore(release): bump version"), branch)

    def test_release_and_hotfix_allow_only_release_chores(self):
        for branch in ("release/1.0.0", "hotfix/1.0.1"):
            self.git("switch", "-q", branch)
            self.assertFalse(self.commit("fix: direct"), branch)
            self.assertTrue(self.commit("chore(release): bump version to 1.0.0 (build 1)"), branch)

    def test_work_branches_are_free(self):
        for branch in ("fix/a", "feature/b", "copilot/c"):
            self.git("switch", "-q", "-c", branch, "main")
            self.assertTrue(self.commit("fix: work"), branch)

    def test_merge_into_protected_branch_is_allowed(self):
        self.git("switch", "-q", "-c", "fix/a", "develop")
        self.assertTrue(self.commit("fix: a"))
        self.git("switch", "-q", "develop")
        result = self.git("merge", "--no-ff", "-q", "fix/a", "-m", "Merge branch 'fix/a' into develop", check=False)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_merge_with_conflicts_resolved_by_hand_is_allowed(self):
        (self.repo / "f").write_text("base\n")
        self.git("add", "f")
        self.git("commit", "-q", "--no-verify", "-m", "base")
        self.git("switch", "-q", "-c", "fix/c")
        (self.repo / "f").write_text("fix\n")
        self.git("commit", "-q", "-am", "fix: c")
        self.git("switch", "-q", "main")
        (self.repo / "f").write_text("other\n")
        self.git("commit", "-q", "--no-verify", "-am", "other")
        self.git("merge", "-q", "fix/c", check=False)
        (self.repo / "f").write_text("fix\n")
        self.git("add", "f")
        self.assertEqual(self.git("commit", "-q", "--no-edit", check=False).returncode, 0)

    def test_detached_head_is_free(self):
        self.git("checkout", "-q", "--detach")
        self.assertTrue(self.commit("detached"))

    def test_no_verify_overrides(self):
        self.git("switch", "-q", "develop")
        result = self.git("commit", "-q", "--allow-empty", "--no-verify", "-m", "fix: on purpose", check=False)
        self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
