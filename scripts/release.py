#!/usr/bin/env python3
"""Prepare signed macOS updates locally; publish only with --publish."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Relay.xcodeproj/project.pbxproj"
REPO = "SilverMarcs/SwiftBeeper"
ACCOUNT = "com.SilverMarcs.Relay.sparkle"
IDENTITY = "Developer ID Application: Zabir Raihan (J52QUTREBS)"
FEED_URL = f"https://github.com/{REPO}/releases/latest/download/appcast.xml"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def xcode_command():
    return ["/usr/bin/xcodebuild"] if os.environ.get("GITHUB_ACTIONS") == "true" else ["xcslot", "xcodebuild"]


def signing_arguments():
    key = os.environ.get("SPARKLE_PRIVATE_KEY_FILE")
    return ["--ed-key-file", key] if key else ["--account", ACCOUNT]


def version_tuple(version):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError(f"Invalid release version: {version}")
    return tuple(map(int, version.split(".")))


def next_version(project, published):
    """An explicit major/minor bump wins; otherwise increment the last release."""
    if version_tuple(project) > version_tuple(published):
        return project
    major, minor, patch = version_tuple(published)
    return f"{major}.{minor}.{patch + 1}"


def published_release():
    return json.loads(run(["gh", "api", f"repos/{REPO}/releases/latest"]))


def published_feed(release):
    asset = next((asset for asset in release["assets"] if asset["name"] == "appcast.xml"), None)
    if asset is None:
        raise RuntimeError("The latest release has no Sparkle feed")
    with urllib.request.urlopen(asset["browser_download_url"], timeout=60) as response:
        return response.read()


def feed_build(feed):
    return max(int(item.findtext(SPARKLE + "version")) for item in ET.fromstring(feed).findall("channel/item"))


def run(args, log=None):
    args = list(map(str, args))
    print("→", " ".join(args), flush=True)
    result = subprocess.run(args, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    if log:
        log.write_text(result.stdout)
    if result.returncode:
        raise RuntimeError(result.stdout[-6000:])
    return result.stdout.strip()


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(file.read()).hexdigest()


def source_fingerprint():
    # File contents stay the same when the prepared changes are committed.
    names = subprocess.check_output(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT
    ).decode().split("\0")
    digest = hashlib.sha256()
    for name in sorted(set(names) - {""}):
        path = ROOT / name
        if not path.exists() and not path.is_symlink():
            continue
        digest.update(name.encode() + b"\0")
        digest.update(str(path.lstat().st_mode).encode() + b"\0")
        digest.update(os.readlink(path).encode() if path.is_symlink() else path.read_bytes())
    return digest.hexdigest()


def setting(name):
    values = re.findall(r'"' + re.escape(name) + r'\[sdk=macosx\*\]" = "?([^";]+)"?;', PROJECT.read_text())
    if len(values) != 2 or len(set(values)) != 1:
        raise RuntimeError(f"Expected matching Debug/Release values for {name}")
    return values[0]


def tools():
    override = os.environ.get("SPARKLE_TOOLS_DIR")
    if override:
        return Path(override)
    home = Path.home()
    patterns = [
        (home / "Library/Developer/xcslot", "Relay-*/*/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"),
        (home / "Library/Caches/xcb/SourcePackages", "Relay-*/artifacts/sparkle/Sparkle/bin"),
        (home / "Library/Developer/Xcode/DerivedData", "*/SourcePackages/artifacts/sparkle/Sparkle/bin"),
        (home / "Library/Caches/xcb/SourcePackages", "*/artifacts/sparkle/Sparkle/bin"),
    ]
    for base, pattern in patterns:
        for candidate in sorted(base.glob(pattern)):
            if all((candidate / name).is_file() for name in ("generate_keys", "sign_update", "generate_appcast")):
                return candidate
    raise RuntimeError("Resolve the project's Swift packages to install Sparkle's tools")


def check():
    for name in (xcode_command()[0], "gh", "xcrun", "codesign", "hdiutil"):
        if not shutil.which(name):
            raise RuntimeError(f"Missing required command: {name}")
    if IDENTITY not in run(["security", "find-identity", "-v", "-p", "codesigning"]):
        raise RuntimeError("Developer ID signing identity is unavailable")
    run(["xcrun", "notarytool", "history", "--keychain-profile", "swiftterminal-notary", "--output-format", "json"])
    if os.environ.get("GITHUB_ACTIONS") == "true":
        # Installation tokens omit the user-specific permissions object. The
        # workflow grants contents:write; verify its repository here instead.
        if run(["gh", "api", f"repos/{REPO}", "--jq", ".full_name"]) != REPO:
            raise RuntimeError("GitHub Actions token cannot access the Relay repository")
    elif run(["gh", "api", f"repos/{REPO}", "--jq", ".permissions.push"]) != "true":
        raise RuntimeError("GitHub account cannot publish to the Relay repository")
    key = os.environ.get("SPARKLE_PRIVATE_KEY_FILE")
    if key:
        # Compare the exported seed with the public key embedded in Relay,
        # without importing the private signing key into another Keychain.
        public_key = subprocess.check_output(["swift", "-e", '''
import Foundation
import CryptoKit
let data = Data(base64Encoded: readLine()!)!
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: data.prefix(32))
print(key.publicKey.rawRepresentation.base64EncodedString())
'''], input=Path(key).read_bytes()).decode().strip()
    else:
        public_key = run([tools() / "generate_keys", "--account", ACCOUNT, "-p"])
    if public_key != setting("RELAY_SPARKLE_PUBLIC_KEY"):
        raise RuntimeError("Relay's Sparkle public key does not match its Keychain account")
    print("Developer ID, notarization, GitHub and Relay's Sparkle signing key are ready.", flush=True)


def notarize(path, log):
    result = json.loads(run(["xcrun", "notarytool", "submit", path, "--keychain-profile",
                             "swiftterminal-notary", "--wait", "--output-format", "json"], log))
    if result["status"] != "Accepted":
        raise RuntimeError(f"Notarization failed: {result}")
    run(["xcrun", "stapler", "staple", path])
    run(["xcrun", "stapler", "validate", path])
    return result


def prepare(version, output, *, build=None, ci=False, previous_feed=None):
    check()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError("Use a release version such as 0.2.1")
    current = setting("MARKETING_VERSION")
    if tuple(map(int, version.split("."))) < tuple(map(int, current.split("."))):
        raise RuntimeError("Release versions must not go backwards")
    if previous_feed is None:
        previous_feed = published_feed(published_release())
    build = build or max(int(setting("CURRENT_PROJECT_VERSION")), feed_build(previous_feed)) + 1
    out = (output or ROOT / ".release" / f"{version}-{build}").resolve()
    out.mkdir(parents=True, exist_ok=False)
    work = out / "work"
    assets = out / "assets"
    work.mkdir()
    assets.mkdir()
    project = PROJECT.read_text()
    for key, value in (("MARKETING_VERSION", version), ("CURRENT_PROJECT_VERSION", str(build))):
        project = re.sub(r'("' + key + r'\[sdk=macosx\*\]" = )[^;]+;', lambda match: match[1] + value + ";", project)
    if not ci:
        PROJECT.write_text(project)
    signing = []
    export_options = ROOT / "Configuration/ExportOptions-macOS.plist"
    if ci:
        profiles = json.loads(Path(os.environ["RELAY_CI_PROFILES"]).read_text())
        signing = ["CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={IDENTITY}",
                   "PROVISIONING_PROFILE_SPECIFIER=$(RELAY_PROFILE_$(TARGET_NAME))",
                   *[f"RELAY_PROFILE_{name}={uuid}" for name, uuid in profiles["targets"].items()],
                   f"MARKETING_VERSION={version}", f"CURRENT_PROJECT_VERSION={build}"]
        options = plistlib.loads(export_options.read_bytes())
        options.update(signingStyle="manual", provisioningProfiles=profiles["bundles"])
        export_options = work / "ExportOptions.plist"
        export_options.write_bytes(plistlib.dumps(options))
    provisioning = [] if ci else ["-allowProvisioningUpdates"]
    run([*xcode_command(), "-project", "Relay.xcodeproj", "-scheme", "Relay", "-configuration", "Release",
         "-destination", "generic/platform=macOS", "-archivePath", work / "Relay.xcarchive",
         *provisioning, *signing, "-quiet", "archive"], out / "archive.log")
    run([*xcode_command(), "-exportArchive", "-archivePath", work / "Relay.xcarchive", "-exportPath", work / "export",
         "-exportOptionsPlist", export_options,
         *provisioning, "-quiet"], out / "export.log")
    app = work / "export/Relay.app"
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["SUFeedURL"] == FEED_URL
    assert info["SUPublicEDKey"] == setting("RELAY_SPARKLE_PUBLIC_KEY")
    assert info["SURequireSignedFeed"] and info["SUVerifyUpdateBeforeExtraction"]
    assert info["CFBundleVersion"] == str(build) and info["CFBundleShortVersionString"] == version
    assert (app / "Contents/Frameworks/Sparkle.framework").exists()
    run(["codesign", "--verify", "--deep", "--strict", app])
    for bundle in (app, app / "Contents/PlugIns/ShareExtension.appex"):
        entitlements = plistlib.loads(subprocess.check_output(
            ["codesign", "-d", "--entitlements", ":-", str(bundle)], stderr=subprocess.DEVNULL))
        assert entitlements["com.apple.security.application-groups"] == ["J52QUTREBS.com.SilverMarcs.Relay"]
        assert not entitlements.get("com.apple.security.get-task-allow", False)
    profile = plistlib.loads(subprocess.check_output(
        ["security", "cms", "-D", "-i", str(app / "Contents/embedded.provisionprofile")], stderr=subprocess.DEVNULL))
    assert profile.get("ProvisionsAllDevices") and not profile.get("ProvisionedDevices")
    binaries = []
    for path in app.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        if "Mach-O" in subprocess.check_output(["file", "-b", str(path)], text=True):
            architectures = subprocess.check_output(["lipo", "-archs", str(path)], text=True).split()
            assert {"arm64", "x86_64"} <= set(architectures), path
            binaries.append(str(path.relative_to(app)))
    assert not list(app.rglob("gomuks.db"))
    run(["ditto", "-c", "-k", "--keepParent", app, work / "app.zip"])
    # Submit the zip, then staple the app that will be copied into the DMG.
    result = json.loads(run(["xcrun", "notarytool", "submit", work / "app.zip", "--keychain-profile",
                             "swiftterminal-notary", "--wait", "--output-format", "json"], out / "app-notary.log"))
    assert result["status"] == "Accepted", result
    run(["xcrun", "stapler", "staple", app])
    run(["xcrun", "stapler", "validate", app])
    run(["spctl", "--assess", "--type", "execute", "--verbose=2", app])
    stage = work / "dmg-stage"
    stage.mkdir()
    run(["ditto", app, stage / "Relay.app"])
    (stage / "Applications").symlink_to("/Applications")
    dmg = assets / "RelayApp.dmg"
    run(["hdiutil", "create", "-volname", "RelayApp", "-srcfolder", stage, "-ov", "-format", "ULFO", dmg])
    run(["codesign", "--force", "--sign", IDENTITY, dmg])
    dmg_notary = notarize(dmg, out / "dmg-notary.log")
    run(["codesign", "--verify", "--strict", dmg])
    run(["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg])
    (assets / "appcast.xml").write_bytes(previous_feed)
    run([tools() / "sign_update", *signing_arguments(), "--verify", assets / "appcast.xml"])
    notes = os.environ.get("RELAY_RELEASE_NOTES")
    if notes:
        shutil.copy2(notes, assets / "RelayApp.html")
    tag = f"v{version}"
    run([tools() / "generate_appcast", *signing_arguments(), "--maximum-deltas", "0",
         "--download-url-prefix", f"https://github.com/{REPO}/releases/download/{tag}/",
         "--link", f"https://github.com/{REPO}", assets], out / "appcast.log")
    run([tools() / "sign_update", *signing_arguments(), "--verify", assets / "appcast.xml"])
    feed = ET.parse(assets / "appcast.xml").getroot()
    item = next(item for item in feed.findall("channel/item") if item.findtext(SPARKLE + "version") == str(build))
    enclosure = item.find("enclosure")
    assert enclosure.attrib["url"] == f"https://github.com/{REPO}/releases/download/{tag}/RelayApp.dmg"
    assert int(enclosure.attrib["length"]) == dmg.stat().st_size
    run([tools() / "sign_update", *signing_arguments(), "--verify", dmg, enclosure.attrib[SPARKLE + "edSignature"]])
    if not ci:
        shutil.copy2(assets / "appcast.xml", ROOT / "appcast.xml")
    checksums = {name: sha(assets / name) for name in ("RelayApp.dmg", "appcast.xml")}
    (assets / "SHA256SUMS.txt").write_text("".join(f"{digest}  {name}\n" for name, digest in checksums.items()))
    report = {"version": version, "build": build, "tag": tag, "sourceFingerprint": source_fingerprint(),
              "sourceBase": run(["git", "rev-parse", "HEAD"]), "checksums": checksums,
              "appNotary": result, "dmgNotary": dmg_notary, "universalBinaries": binaries,
              "gatekeeper": "accepted app and DMG", "sparkleSignatures": "verified feed and DMG",
              "appGroup": "J52QUTREBS.com.SilverMarcs.Relay", "runtimeLaunched": False}
    (out / "release.json").write_text(json.dumps(report, indent=2) + "\n")
    shutil.rmtree(work)
    for log in out.glob("*.log"):
        log.unlink()
    print(f"Prepared {version} ({build}) in {out}. Nothing was committed, pushed, installed or published.")


def publish(out, *, ci=False):
    check()
    out = out.resolve()
    report = json.loads((out / "release.json").read_text())
    if run(["git", "status", "--porcelain=v1", "--untracked-files=all"]):
        raise RuntimeError("Commit the prepared source and appcast before publishing")
    if not ci and run(["git", "branch", "--show-current"]) != "main":
        raise RuntimeError("Merge the prepared source into main before publishing")
    if source_fingerprint() != report["sourceFingerprint"]:
        raise RuntimeError("The source has changed since this build; prepare a new build")
    head = run(["git", "rev-parse", "HEAD"])
    if ci:
        if head != os.environ.get("GITHUB_SHA") or os.environ.get("GITHUB_REPOSITORY") != REPO:
            raise RuntimeError("CI may only publish its checked-out main commit")
        run(["git", "fetch", "--no-tags", "origin", "main"])
        run(["git", "merge-base", "--is-ancestor", head, "FETCH_HEAD"])
    else:
        remote = run(["git", "ls-remote", f"https://github.com/{REPO}.git", "refs/heads/main"]).split()[0]
        if remote != head:
            raise RuntimeError("Push the prepared main commit before publishing")
    assets = out / "assets"
    for name, digest in report["checksums"].items():
        assert sha(assets / name) == digest, name
    run([tools() / "sign_update", *signing_arguments(), "--verify", assets / "appcast.xml"])
    tag = report["tag"]
    files = [assets / name for name in (*report["checksums"], "SHA256SUMS.txt")]
    existing = subprocess.run(["gh", "release", "view", tag, "--repo", REPO,
                               "--json", "isDraft,targetCommitish"], capture_output=True, text=True)
    if existing.returncode == 0:
        draft = json.loads(existing.stdout)
        if not draft["isDraft"] or draft["targetCommitish"] != head:
            raise RuntimeError("Refusing to overwrite an existing release for another build")
        run(["gh", "release", "upload", tag, "--repo", REPO, "--clobber", *files])
    else:
        run(["gh", "release", "create", tag, "--repo", REPO, "--target", head, "--draft",
         "--title", f"Relay {report['version']}", "--notes",
         f"Signed and notarized universal macOS build {report['build']}. Includes Sparkle updates.", *files])
    downloaded = out / "download-check"
    run(["gh", "release", "download", tag, "--repo", REPO, "--dir", downloaded])
    for name, digest in report["checksums"].items():
        assert sha(downloaded / name) == digest, name
    shutil.rmtree(downloaded)
    # The stable /latest/download/appcast.xml URL changes only after all assets are ready.
    run(["gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest"])
    request = urllib.request.Request(FEED_URL, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=60) as response:
        assert hashlib.sha256(response.read()).hexdigest() == report["checksums"]["appcast.xml"]
    print(f"Published https://github.com/{REPO}/releases/tag/{tag}")


def automatic_release(out):
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise RuntimeError("Automatic releases run only from main in GitHub Actions")
    head = run(["git", "rev-parse", "HEAD"])
    pages = json.loads(run(["gh", "api", f"repos/{REPO}/releases?per_page=100", "--paginate", "--slurp"]))
    if any(not release["draft"] and release["target_commitish"] == head for page in pages for release in page):
        print("This commit already has a published release; no duplicate created.")
        return
    latest = published_release()
    feed = published_feed(latest)
    version = next_version(setting("MARKETING_VERSION"), latest["tag_name"].removeprefix("v"))
    build = max(int(setting("CURRENT_PROJECT_VERSION")), feed_build(feed)) + 1
    prepare(version, out, build=build, ci=True, previous_feed=feed)
    publish(out, ci=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true", help="verify local signing and hosting prerequisites")
    action.add_argument("--prepare", metavar="VERSION", help="build locally and update macOS version/appcast")
    action.add_argument("--publish", type=Path, metavar="OUTPUT", help="publish a prepared build from clean, pushed main")
    action.add_argument("--auto", type=Path, metavar="OUTPUT", help="release this main commit from GitHub Actions")
    parser.add_argument("--output", type=Path, help="new output directory for --prepare (default: .release/VERSION-BUILD)")
    args = parser.parse_args()
    if args.output and not args.prepare:
        parser.error("--output requires --prepare")
    if args.check:
        check()
    elif args.prepare:
        prepare(args.prepare, args.output)
    elif args.auto:
        automatic_release(args.auto)
    else:
        publish(args.publish)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, AssertionError, subprocess.CalledProcessError) as error:
        sys.exit(f"Release stopped: {error}")
