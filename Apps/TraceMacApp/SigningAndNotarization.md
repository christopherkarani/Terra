# Signing + Notarization (Direct Distribution)

This project is set up for **Developer ID** signing and **notarization** so TraceMacApp can be distributed outside the Mac App Store.

## Xcode project settings

- Hardened Runtime is enabled for Release builds.
- An entitlements file is configured: `Apps/TraceMacApp/TraceMacApp.entitlements`.

## Recommended workflow

Use the scripts in `Scripts/release/`:

1. Build a signed `.app`
2. Package a `.dmg`
3. Notarize + staple the `.dmg`

## Notarytool setup

The scripts assume you use a Keychain profile created with:

`xcrun notarytool store-credentials`

Then export the profile name:

`export APPLE_NOTARYTOOL_PROFILE="your-profile-name"`

## Environment variables

- `TRACE_MAC_APP_SIGNING_IDENTITY` (example: `Developer ID Application: Your Company (TEAMID)`)
- `APPLE_NOTARYTOOL_PROFILE` (recommended)

## Output

Artifacts are written under `./.build/releases/TraceMacApp/<version>/`.

## Mac App Store notes

For App Store distribution:

- Use the App Sandbox (different entitlements).
- Do not use Sparkle (App Store provides updates).
- Licensing uses App Store receipt validation instead of license keys.

