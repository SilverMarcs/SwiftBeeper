# macOS releases

## Automatic releases

Every push to `main` starts `.github/workflows/sparkle-release.yml` on a
GitHub-hosted `xcode-27` runner with Xcode 27.2. It archives a universal Mac app,
signs with Developer ID, notarizes and staples the app and DMG, signs the
Sparkle feed and DMG, verifies the uploaded assets, and publishes a GitHub
release. The Mac does not need to be online. Pull requests never run this job.

The patch version and build number advance from the latest published release.
An explicit higher macOS marketing version in the project is respected. CI
passes these versions to Xcode rather than committing generated files back to
`main`, so releases do not trigger a loop. Release tags point at the source
commit that triggered the run; its runtime version is recorded in the assets
and release report. The signed feed includes the latest published history.

Runs are serialized. GitHub keeps the latest pending run during a burst of
pushes. Re-running an already published commit creates no duplicate; a failed
run can replace only its own unpublished draft. A draft for another commit or
an already published release is never overwritten.

The workflow uses the built-in `GITHUB_TOKEN` with `contents: write`. Signing
inputs are encrypted repository secrets, never files committed to Git:

| Secret | Value |
| --- | --- |
| `RELAY_CERTIFICATE_P12` | Base64 of the Developer ID identity exported from the Mac |
| `RELAY_CERTIFICATE_PASSWORD` | Random password protecting that export |
| `RELAY_MAIN_PROFILE` | Base64 of Relay's all-device Mac provisioning profile |
| `RELAY_NOTIFICATION_PROFILE` | Base64 of the notification extension's Mac profile |
| `RELAY_NOTARY_API_KEY` | App Store Connect private API key used by notarization |
| `RELAY_NOTARY_KEY_ID` | API key identifier |
| `RELAY_NOTARY_ISSUER_ID` | API key issuer identifier |
| `RELAY_SPARKLE_PRIVATE_KEY` | Relay's exported EdDSA signing seed |
| `RELAY_PUSH_CONFIGURATION` | Contents of the existing private push configuration |

The runner imports the identity into a temporary Keychain, installs the two
Developer ID profiles, and removes credentials in an `always()` cleanup step.
Sparkle signing reads a protected temporary key file. No App Store upload or
iOS/Sqim build is performed by this workflow.

To inspect or retry a run:

```sh
gh run list --workflow sparkle-release.yml
gh run view RUN_ID --log-failed
gh run rerun RUN_ID
```

`workflow_dispatch` also supports a manual run on `main`.

## Manual releases

Relay's direct-download Mac app uses Sparkle. Release builds check for updates
using Sparkle's standard UI and schedule; **Relay → Check for Updates…** checks
manually. Debug builds leave the updater disabled. Sparkle is linked only on
macOS, and the macOS version/build overrides do not change iOS versions.

The stable feed is
`https://github.com/SilverMarcs/SwiftBeeper/releases/latest/download/appcast.xml`.
Each GitHub release contains `RelayApp.dmg`, `appcast.xml`, and `SHA256SUMS.txt`.
The feed and DMG are signed with Relay's EdDSA key. The app and DMG are also
Developer ID signed, notarized, and stapled. Existing installations without
Sparkle need one manual installation of the first Sparkle-enabled release.

## Local prerequisites

- Xcode and the `xcslot` build wrapper, with project packages resolved.
- Developer ID identity `Developer ID Application: Zabir Raihan (J52QUTREBS)`.
- Notarization Keychain profile `swiftterminal-notary`.
- Sparkle Keychain account `com.SilverMarcs.Relay.sparkle`, matching the public
  key in the project's macOS Info.plist build settings. Local signing uses
  Keychain; CI uses the encrypted secret above. Never add the private key to Git.
- `gh` authenticated with write access to `SilverMarcs/SwiftBeeper`.
- The usual ignored `App/Configuration/*.private.json` files in the checkout.

macOS may request Keychain access the first time a Sparkle tool version uses
the signing key. Approve that request locally in the system dialog; never
send the Mac password through chat or put it in a release script.

```sh
python3 scripts/release.py --check
python3 scripts/release.py --prepare 0.2.1
```

Preparation advances the macOS build number beyond both the project and
published feed, archives a universal Release through `xcslot`, exports with Developer ID, verifies app-group access and
all-device provisioning, notarizes and staples the app and DMG, and generates
and verifies Sparkle's signed feed and update. It updates `appcast.xml` in the
checkout and retains the assets and a verification report under `.release/`.
Use `--output /absolute/new/directory` to keep them elsewhere. Failed preparations
retain build outputs and logs for inspection; successful ones remove temporary
archive/export/staging files. Preparation never launches or installs Relay.

## Publishing

Review and commit the prepared source, package lockfile, version settings and
appcast, merge into `main`, and push when authorized. Then pass the prepared
output directory:

```sh
python3 scripts/release.py --publish .release/0.2.1-2
```

Publishing requires clean, pushed `main` whose source matches the prepared
build. It creates a draft GitHub release, uploads and downloads the assets to
verify their hashes, then publishes it as latest. The stable feed URL begins
serving the new feed only when that release is published. No expiring file
host is involved. The script does not commit or push source changes.

If publishing stops after creating a draft, inspect and fix that draft before
retrying; it deliberately does not overwrite existing release tags or assets.
For the first release, install the DMG manually. A complete update installation
test requires two genuine Sparkle-enabled release builds; signing and build
checks alone do not prove that end-to-end update.
