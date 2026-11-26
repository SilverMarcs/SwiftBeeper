#!/usr/bin/env python3
"""Install release credentials in a disposable GitHub-hosted Mac Keychain."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import secrets
import shlex
import shutil
import subprocess
import sys


def command(args):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True)
    if result.returncode:
        # Never echo arguments or credential-bearing subprocess output.
        raise RuntimeError(f"Credential operation {args[0]} failed ({result.returncode})")
    return result.stdout


def write_private(path, content):
    path.write_bytes(content)
    path.chmod(0o600)


def install(root):
    root.mkdir(mode=0o700, parents=True)
    keychain = root / "signing.keychain-db"
    original = shlex.split(command(["security", "list-keychains", "-d", "user"]))
    state = {"keychain": str(keychain), "originalKeychains": original, "profiles": [], "config": None}
    state_file = root / "state.json"
    state_file.write_text(json.dumps(state))
    password = secrets.token_urlsafe(32)
    command(["security", "create-keychain", "-p", password, keychain])
    command(["security", "set-keychain-settings", "-lut", "21600", keychain])
    command(["security", "unlock-keychain", "-p", password, keychain])
    command(["security", "list-keychains", "-d", "user", "-s", keychain, *original])
    p12 = root / "certificate.p12"
    write_private(p12, base64.b64decode(os.environ["RELAY_CERTIFICATE_P12"], validate=True))
    command(["security", "import", p12, "-k", keychain, "-P", os.environ["RELAY_CERTIFICATE_PASSWORD"],
             "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"])
    command(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-s", "-k", password, keychain])
    mapping = {"targets": {}, "bundles": {}}
    for name, target, bundle in [
        ("RELAY_MAIN_PROFILE", "Relay", "com.SilverMarcs.Relay"),
        ("RELAY_NOTIFICATION_PROFILE", "NotificationService", "com.SilverMarcs.Relay.NotificationService"),
    ]:
        data = base64.b64decode(os.environ[name], validate=True)
        temporary = root / f"{target}.provisionprofile"
        write_private(temporary, data)
        profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(temporary)], stderr=subprocess.DEVNULL))
        identifier = profile["Entitlements"]["com.apple.application-identifier"]
        if identifier != "J52QUTREBS." + bundle or not profile.get("ProvisionsAllDevices"):
            raise RuntimeError("Unexpected Developer ID provisioning profile")
        for directory in [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                          Path.home() / "Library/MobileDevice/Provisioning Profiles"]:
            directory.mkdir(parents=True, exist_ok=True)
            destination = directory / (profile["UUID"] + ".provisionprofile")
            if destination.exists():
                raise RuntimeError("Refusing to replace a provisioning profile already on the runner")
            write_private(destination, data)
            state["profiles"].append(str(destination))
            state_file.write_text(json.dumps(state))
        mapping["targets"][target] = profile["UUID"]
        mapping["bundles"][bundle] = profile["UUID"]
    write_private(root / "profiles.json", json.dumps(mapping).encode())
    key = root / "AuthKey.p8"
    write_private(key, os.environ["RELAY_NOTARY_API_KEY"].encode())
    command(["xcrun", "notarytool", "store-credentials", "swiftterminal-notary", "--key", key,
             "--key-id", os.environ["RELAY_NOTARY_KEY_ID"], "--issuer", os.environ["RELAY_NOTARY_ISSUER_ID"],
             "--keychain", keychain])
    write_private(root / "sparkle-key", os.environ["RELAY_SPARKLE_PRIVATE_KEY"].strip().encode() + b"\n")
    configuration = Path.cwd() / "App/Configuration/PushConfiguration.private.json"
    if configuration.exists():
        raise RuntimeError("Refusing to replace an existing push configuration")
    data = os.environ["RELAY_PUSH_CONFIGURATION"]
    json.loads(data)
    configuration.parent.mkdir(parents=True, exist_ok=True)
    write_private(configuration, data.encode())
    state["config"] = str(configuration)
    state_file.write_text(json.dumps(state))
    with open(os.environ["GITHUB_ENV"], "a") as environment:
        environment.write(f"RELAY_CI_PROFILES={root / 'profiles.json'}\n")
        environment.write(f"SPARKLE_PRIVATE_KEY_FILE={root / 'sparkle-key'}\n")
    print("Installed isolated signing, provisioning, notarization and Sparkle credentials.")


def cleanup(root):
    state_file = root / "state.json"
    if state_file.exists():
        state = json.loads(state_file.read_text())
        command(["security", "list-keychains", "-d", "user", "-s", *state["originalKeychains"]])
        if Path(state["keychain"]).exists():
            command(["security", "delete-keychain", state["keychain"]])
        for profile in state["profiles"]:
            Path(profile).unlink(missing_ok=True)
        if state["config"]:
            Path(state["config"]).unlink(missing_ok=True)
    if root.exists():
        shutil.rmtree(root)
    print("Removed runner signing credentials.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["install", "cleanup"])
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        (install if args.action == "install" else cleanup)(args.directory)
    except (RuntimeError, KeyError, ValueError, subprocess.CalledProcessError):
        sys.exit("Credential setup/cleanup failed; secret values have not been logged.")
