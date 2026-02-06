# Updates (Sparkle)

TraceMacApp supports Sparkle-style updates for **direct distribution**.

## Setup

1. Add the Sparkle framework to the Xcode project target.
2. Configure `SUFeedURL` in `Apps/TraceMacApp/Info.plist`.
3. Generate a Sparkle signing key and publish the public key in the app (Sparkle expects signed updates).
4. Host:
   - the DMG (or zipped app) for each version
   - the appcast XML

## Default behavior

- Automatic update checks should be disabled by default for privacy.
- Users can manually trigger “Check for Updates…”.

## Notes

- For Mac App Store distribution, Sparkle is not used; updates are handled by the App Store and licensing uses receipt validation.

