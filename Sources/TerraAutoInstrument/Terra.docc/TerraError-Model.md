# TerraError Model

Lifecycle/configuration failures use ``TerraCore/Terra/TerraError``.

## Stable Error Codes

- ``TerraCore/Terra/TerraError/Code/invalid_endpoint``
- ``TerraCore/Terra/TerraError/Code/persistence_setup_failed``
- ``TerraCore/Terra/TerraError/Code/already_started``
- ``TerraCore/Terra/TerraError/Code/invalid_lifecycle_state``
- ``TerraCore/Terra/TerraError/Code/start_failed``
- ``TerraCore/Terra/TerraError/Code/reconfigure_failed``

## Handling Pattern

```swift
import Terra

let config = Terra.Configuration(preset: .quickstart)

do {
  try await Terra.start(config)
} catch let error as Terra.TerraError {
  print("TerraError code: \(error.code.rawValue)")
  print("Message: \(error.message)")
  print("Hint: \(error.remediationHint)")
  print("Context: \(error.context)")
} catch {
  print("Non-Terra error: \(error)")
}
```

`error.code` is the branching key; `context` and `underlying` provide diagnostics.
