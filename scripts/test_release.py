"""Exercise publication guards without contacting GitHub or the Keychain."""
import hashlib
import io
import json
from pathlib import Path
import tempfile
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


if __name__ == "__main__":
    unittest.main()
