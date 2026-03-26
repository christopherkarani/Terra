# TerraError Model

Lifecycle, guidance, and configuration failures use ``Terra/TerraError``.

## Stable Error Codes

- ``Terra/TerraError/Code/invalid_endpoint``
- ``Terra/TerraError/Code/persistence_setup_failed``
- ``Terra/TerraError/Code/already_started``
- ``Terra/TerraError/Code/invalid_lifecycle_state``
- ``Terra/TerraError/Code/start_failed``
- ``Terra/TerraError/Code/reconfigure_failed``
- ``Terra/TerraError/Code/guidance``
- ``Terra/TerraError/Code/wrong_api_for_workflow``
- ``Terra/TerraError/Code/context_not_propagated``
- ``Terra/TerraError/Code/misconfiguration``
- ``Terra/TerraError/Code/invalid_operation``

## Handling Pattern

```swift
do {
  try await Terra.start(config)
} catch let error as Terra.TerraError {
  print(error.code.rawValue)
  print(error.message)
  print(error.recoverySuggestion)
}
```

Use ``Terra/TerraError/code`` as the branching key.
Use ``Terra/TerraError/context`` and ``Terra/TerraError/underlying`` for diagnostics.

## Workflow Guidance

Workflow-focused guidance errors surface when callers choose the wrong tracing shape:

- `wrong_api_for_workflow` when a closure-scoped child operation is the wrong root entry point for a multi-step workflow
- `context_not_propagated` when detached work drops Terra context and should move to `SpanHandle.detached(...)`
- `invalid_operation` when a span handle has ended or the API sequence cannot succeed
