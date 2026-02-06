# TraceMacApp Release Checklist

This checklist is for **direct distribution** (Developer ID + notarized DMG) and assumes Sparkle is used for updates.

## 1) Preconditions

- [ ] You have a **Developer ID Application** signing certificate installed.
- [ ] You have a notarization setup for `notarytool` (recommended: Keychain profile).
- [ ] `Apps/TraceMacApp/Info.plist` version (`CFBundleShortVersionString`) and build (`CFBundleVersion`) are updated.
- [ ] `CHANGELOG.md` is updated.
- [ ] The Sparkle appcast URL and signing key are configured (see `Apps/TraceMacApp/Updates.md`).

## 2) Validate

- [ ] `swift test` passes.
- [ ] `xcodebuild -project Apps/TraceMacApp/TraceMacApp.xcodeproj -scheme TraceMacApp -configuration Release build` passes.
- [ ] Manual sanity:
  - [ ] App launches and shows traces.
  - [ ] “Open Traces Folder” works.
  - [ ] Folder watch toggles and reloads traces.
  - [ ] Licensing UI works (trial + activation).
  - [ ] “Export Diagnostics…” produces a zip.
  - [ ] “Check for Updates…” opens Sparkle UI (if feed configured).

## 3) Build + Notarize

- [ ] Build a signed Release app archive.
- [ ] Create a DMG.
- [ ] Notarize the DMG and staple.

Recommended: use the scripts in `Scripts/release/` (see `Apps/TraceMacApp/SigningAndNotarization.md`).

## 4) Publish

- [ ] Upload the notarized DMG to your download host.
- [ ] Publish a new Sparkle appcast entry pointing at the DMG.
- [ ] Create a Git tag for the release.

