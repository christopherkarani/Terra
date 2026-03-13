# TerraError Model

Lifecycle/configuration failures use ``Terra/TerraError``.

## Stable Error Codes

- ``Terra/TerraError/Code/invalid_endpoint``
- ``Terra/TerraError/Code/persistence_setup_failed``
- ``Terra/TerraError/Code/already_started``
- ``Terra/TerraError/Code/invalid_lifecycle_state``
- ``Terra/TerraError/Code/start_failed``
- ``Terra/TerraError/Code/reconfigure_failed``

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

Use ``Terra/TerraError/code`` as the branching key.
Use ``Terra/TerraError/context`` and ``Terra/TerraError/underlying`` for diagnostics.
