# Licensing (Direct Distribution)

TraceMacApp supports **offline-verifiable** license keys (Ed25519 signatures) plus a **14‑day trial**.

## Configure the public key

Set `TraceMacAppLicensePublicKey` in `Apps/TraceMacApp/Info.plist` to your Ed25519 **public key** (base64url, raw 32‑byte representation).

If this key is missing/invalid, activation will show “Licensing is not configured”.

## License key format

License keys are three dot-separated components:

`TERRA-LICENSE-1.<payload_base64url>.<signature_base64url>`

Where:
- `payload_base64url` decodes to JSON (see `LicensePayload` in `Sources/TraceMacApp/LicensePayload.swift`)
- `signature_base64url` is an Ed25519 signature of the raw payload bytes

## Expiration + offline grace

- Licenses may include an `expires_at` timestamp.
- TraceMacApp honors an offline grace window (`grace_days`) after expiration (default 7).

## App Store builds

For Mac App Store distribution, license keys are not used:
- updates are handled by the App Store
- licensing is based on receipt validation

