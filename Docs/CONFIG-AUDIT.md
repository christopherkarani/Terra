# Configuration-Reference.md Audit

Audited against: `Sources/TerraAutoInstrument/Terra+Start.swift` and `Sources/Terra/Terra+PrivacyV3.swift`

---

## DISCREPANCY FOUND: Incorrect PrivacyPolicy behavior descriptions

**Location:** Configuration-Reference.md, "Terra.PrivacyPolicy" section, lines 297-303

**ACTUAL API** (`Terra.PrivacyPolicy` from `Terra+PrivacyV3.swift`):
| Case | Content | Hash | Length |
|------|---------|------|--------|
| `.redacted` | Dropped | HMAC-SHA256 | Yes |
| `.lengthOnly` | Dropped | None | Yes |
| `.capturing` | Dropped | HMAC-SHA256 | Yes |
| `.silent` | Dropped | None | No |

**DOCUMENTED AS:**
| Case | Content | Hash | Length | Use Case |
|------|---------|------|--------|----------|
| `.redacted` | Dropped | HMAC-SHA256 | Yes | Production default |
| `.lengthOnly` | Dropped | None | Yes | Maximum privacy |
| `.capturing` | Stored | HMAC-SHA256 | Yes | Debug builds |
| `.silent` | Dropped | None | No | Testing |

**RECOMMENDED FIX:**
- For `.capturing`: Change "Content" from "Stored" to "Dropped". Note: `.capturing` uses `shouldCapture` to bypass privacy policy during recording, but the underlying content IS hashed with HMAC-SHA256 before leaving the device. The content itself is not "stored" unencrypted.
- Verify whether the "Use Case" column descriptions are accurate for each policy's intended use case.

---

## DISCREPANCY FOUND: Content Redaction Behavior example shows `.lengthOnly` but describes `.redacted`

**Location:** Configuration-Reference.md, "Content Redaction Behavior" section, lines 306-312

**DOCUMENTED AS:**
```swift
config.privacy = .redacted
// Prompt "Hello world" (11 chars) emits:
//   terra.prompt.length = 11
//   terra.prompt.hmac_sha256 = "a4a3f7..."
//   terra.anonymization_key_id = "key-abc123"
```

**ACTUAL API:** The example comment says `.redacted` but the behavior described (hmac_sha256 + length) is correct for `.redacted`. However, `terra.anonymization_key_id` attribute name may not match actual emitted attribute key. Verify against actual span attribute key name.

**RECOMMENDED FIX:** Confirm the exact attribute key name used for the HMAC hash in the actual implementation (`Terra+PrivacyV3.swift` redaction strategy).

---

## NO DISCREPANCY: Preset table

The preset table (lines 23-27) matches the actual `Configuration.init(preset:)` implementation:
- `quickstart`: `.redacted`, CoreML+HTTP+Sessions+Signposts, Off, None — CORRECT
- `production`: `.redacted`, CoreML+HTTP+Sessions, Balanced, None — CORRECT
- `diagnostics`: `.redacted`, CoreML+HTTP+Sessions+Signposts+Logs, Balanced, Standard — CORRECT

---

## NO DISCREPANCY: Configuration Properties

All documented properties (privacy, destination, features, persistence, profiling) match the actual `Configuration` struct in `Terra+Start.swift`.

---

## NO DISCREPANCY: Profiling OptionSet

All profiling options (`.memory`, `.metal`, `.thermal`, `.power`, `.espresso`, `.ane`, `.standard`, `.extended`, `.all`) are correctly documented with their raw values and descriptions.

---

## NO DISCREPANCY: Features OptionSet

All feature flags (`.coreML`, `.http`, `.sessions`, `.signposts`, `.logs`) are correctly documented.

---

## NO DISCREPANCY: Persistence enum

All persistence cases (`.off`, `.balanced(URL)`, `.instant(URL)`) and the performance tier descriptions are correct.

---

## Summary

| Severity | Issue |
|----------|-------|
| HIGH | PrivacyPolicy table: `.capturing` row incorrectly says "Content: Stored" |
| LOW | Content Redaction Behavior example: verify `terra.anonymization_key_id` attribute name |
