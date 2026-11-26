"""Exercise publication guards without contacting GitHub or the Keychain."""
import hashlib
import io
import json
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

import release


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.out = Path(self.temporary.name)
        assets = self.out / "assets"
        assets.mkdir()
        self.contents = {"RelayApp.dmg": b"signed image", "appcast.xml": b"signed feed"}
        checksums = {}
        for name, content in self.contents.items():
            (assets / name).write_bytes(content)
            checksums[name] = hashlib.sha256(content).hexdigest()
        (assets / "SHA256SUMS.txt").write_text("checksums")
        (self.out / "release.json").write_text(json.dumps({
            "tag": "v0.2.1", "version": "0.2.1", "build": 2,
            "sourceFingerprint": "prepared", "checksums": checksums,
        }))
        self.status = ""
        self.branch = "main"
        self.remote = "head"
        self.corrupt_download = False
        self.commands = []
        self.addCleanup(patch.stopall)
        patch.object(release, "check").start()
        patch.object(release, "tools", return_value=Path("/tools")).start()
        self.fingerprint = patch.object(release, "source_fingerprint", return_value="prepared").start()
        patch.object(release, "run", side_effect=self.run_command).start()
        self.existing = patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "")).start()
        patch.object(release.urllib.request, "urlopen", return_value=io.BytesIO(self.contents["appcast.xml"])).start()

    def run_command(self, args):
        args = list(map(str, args))
        self.commands.append(args)
        if args[:3] == ["git", "status", "--porcelain=v1"]:
            return self.status
        if args[:3] == ["git", "branch", "--show-current"]:
            return self.branch
        if args[:3] == ["git", "rev-parse", "HEAD"]:
            return "head"
        if args[:2] == ["git", "ls-remote"]:
            return self.remote + "\trefs/heads/main"
        if args[:3] == ["gh", "release", "download"]:
            destination = Path(args[args.index("--dir") + 1])
            destination.mkdir()
            for name, content in self.contents.items():
                (destination / name).write_bytes(b"wrong bytes" if self.corrupt_download else content)
        return ""

    def assert_blocked(self, text):
        with self.assertRaisesRegex(RuntimeError, text):
            release.publish(self.out)
        self.assertFalse(any(command[:2] == ["gh", "release"] for command in self.commands))

    def test_dirty_source_cannot_publish(self):
        self.status = " M App/RelayApp.swift"
        self.assert_blocked("Commit the prepared source")

    def test_unmerged_worktree_cannot_publish(self):
        self.branch = "feature"
        self.assert_blocked("Merge the prepared source")

    def test_changed_source_cannot_publish(self):
        self.fingerprint.return_value = "new edits"
        self.assert_blocked("source has changed")

    def test_unpushed_main_cannot_publish(self):
        self.remote = "older-head"
        self.assert_blocked("Push the prepared main")

    def test_local_tampering_cannot_create_a_release(self):
        (self.out / "assets/RelayApp.dmg").write_bytes(b"tampered")
        with self.assertRaises(AssertionError):
            release.publish(self.out)
        self.assertFalse(any(command[:2] == ["gh", "release"] for command in self.commands))

    def test_bad_download_keeps_the_release_a_draft(self):
        self.corrupt_download = True
        with self.assertRaises(AssertionError):
            release.publish(self.out)
        self.assertTrue(any(command[:3] == ["gh", "release", "create"] for command in self.commands))
        self.assertFalse(any(command[:3] == ["gh", "release", "edit"] for command in self.commands))

    def test_only_verified_assets_are_published_as_latest(self):
        release.publish(self.out)
        commands = [command for command in self.commands if command[:2] == ["gh", "release"]]
        self.assertEqual([command[2] for command in commands], ["create", "download", "edit"])
        self.assertIn("--draft", commands[0])
        self.assertIn("--draft=false", commands[-1])
        self.assertIn("--latest", commands[-1])

    def test_retry_can_replace_only_its_own_draft(self):
        self.existing.return_value = subprocess.CompletedProcess([], 0, json.dumps({"isDraft": True, "targetCommitish": "head"}), "")
        release.publish(self.out)
        commands = [command[2] for command in self.commands if command[:2] == ["gh", "release"]]
        self.assertEqual(commands, ["upload", "download", "edit"])

    def test_published_release_cannot_be_overwritten(self):
        self.existing.return_value = subprocess.CompletedProcess([], 0, json.dumps({"isDraft": False, "targetCommitish": "head"}), "")
        self.assert_blocked("Refusing to overwrite")

    def test_another_commits_draft_cannot_be_overwritten(self):
        self.existing.return_value = subprocess.CompletedProcess([], 0, json.dumps({"isDraft": True, "targetCommitish": "someone-else"}), "")
        self.assert_blocked("Refusing to overwrite")

    def test_ci_checks_main_ancestry_instead_of_requiring_latest_head(self):
        self.remote = "newer-push"
        with patch.dict(release.os.environ, {"GITHUB_SHA": "head", "GITHUB_REPOSITORY": release.REPO}):
            release.publish(self.out, ci=True)
        self.assertIn(["git", "merge-base", "--is-ancestor", "head", "FETCH_HEAD"], self.commands)

    def test_ci_cannot_publish_a_different_commit(self):
        with patch.dict(release.os.environ, {"GITHUB_SHA": "different", "GITHUB_REPOSITORY": release.REPO}):
            with self.assertRaisesRegex(RuntimeError, "checked-out main commit"):
                release.publish(self.out, ci=True)
        self.assertFalse(any(command[:2] == ["gh", "release"] for command in self.commands))


class CredentialCheckTests(unittest.TestCase):
    def test_actions_token_does_not_require_user_permissions_metadata(self):
        with patch.dict(release.os.environ, {"GITHUB_ACTIONS": "true", "SPARKLE_PRIVATE_KEY_FILE": ""}), \
                patch.object(release.shutil, "which", return_value="/tool"), \
                patch.object(release, "tools", return_value=Path("/tools")), \
                patch.object(release, "setting", return_value="public-key"), \
                patch.object(release, "run", side_effect=[release.IDENTITY, "{}", release.REPO, "public-key"]) as run:
            release.check()
        self.assertIn(["gh", "api", f"repos/{release.REPO}", "--jq", ".full_name"], [call.args[0] for call in run.call_args_list])

    def test_local_token_still_requires_push_access(self):
        with patch.dict(release.os.environ, {"GITHUB_ACTIONS": "false"}), \
                patch.object(release.shutil, "which", return_value="/tool"), \
                patch.object(release, "run", side_effect=[release.IDENTITY, "{}", "false"]):
            with self.assertRaisesRegex(RuntimeError, "cannot publish"):
                release.check()


class VersionTests(unittest.TestCase):
    def test_automatic_patch_follows_published_version(self):
        self.assertEqual(release.next_version("0.2.6", "0.2.9"), "0.2.10")

    def test_explicit_source_version_bump_is_respected(self):
        self.assertEqual(release.next_version("0.3.0", "0.2.9"), "0.3.0")

    def test_invalid_versions_are_rejected(self):
        with self.assertRaises(RuntimeError):
            release.next_version("0.3", "0.2.9")

    def test_feed_build_uses_highest_build_not_item_order(self):
        feed = '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>7</sparkle:version></item><item><sparkle:version>12</sparkle:version></item></channel></rss>'
        self.assertEqual(release.feed_build(feed.encode()), 12)

    def test_already_published_commit_is_idempotent(self):
        pages = [[{"draft": False, "target_commitish": "head"}]]
        with patch.dict(release.os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main"}), \
                patch.object(release, "run", side_effect=["head", json.dumps(pages)]), \
                patch.object(release, "prepare") as prepare, patch.object(release, "publish") as publish:
            release.automatic_release(Path("/unused"))
        prepare.assert_not_called()
        publish.assert_not_called()

    def test_automatic_release_rejects_non_main_runs(self):
        with patch.dict(release.os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/feature"}):
            with self.assertRaisesRegex(RuntimeError, "only from main"):
                release.automatic_release(Path("/unused"))


if __name__ == "__main__":
    unittest.main()
