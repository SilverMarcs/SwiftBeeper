# macOS releases

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

- Xcode and the `xcb` build wrapper, with project packages resolved.
- Developer ID identity `Developer ID Application: Zabir Raihan (J52QUTREBS)`.
- Notarization Keychain profile `swiftterminal-notary`.
- Sparkle Keychain account `com.SilverMarcs.Relay.sparkle`, matching the public
  key in the project's macOS Info.plist build settings. The private key stays
  in Keychain; it must never be added to this repository.
- `gh` authenticated with write access to `SilverMarcs/SwiftBeeper`.
- The usual ignored `App/Configuration/*.private.json` files in the checkout.

macOS may request Keychain access the first time a Sparkle tool version uses
the signing key. Approve that request locally in the system dialog; never
send the Mac password through chat or put it in a release script.

```sh
python3 scripts/release.py --check
python3 scripts/release.py --prepare 0.2.1
```

Preparation increments the macOS build number, archives a universal Release
through `xcb`, exports with Developer ID, verifies app-group access and
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
