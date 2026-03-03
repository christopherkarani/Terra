# Terra Migration: v1 to v2

## Core call-site mapping

| v1 | v2 |
| --- | --- |
| `Terra.withInferenceSpan(...) { ... }` | `Terra.inference(...).run { ... }` |
| `Terra.withStreamingInferenceSpan(...) { ... }` | `Terra.stream(...).run { ... }` |
| `Terra.withEmbeddingSpan(...) { ... }` | `Terra.embedding(...).run { ... }` |
| `Terra.withAgentInvocationSpan(...) { ... }` | `Terra.agent(...).run { ... }` |
| `Terra.withToolExecutionSpan(...) { ... }` | `Terra.tool(...).run { ... }` |
| `Terra.withSafetyCheckSpan(...) { ... }` | `Terra.safetyCheck(...).run { ... }` |

## Common metadata mapping

| v1 scope helper | v2 fluent helper |
| --- | --- |
| `scope.setRuntime("mlx")` | `.runtime("mlx")` |
| `scope.setProvider("openai")` | `.provider("openai")` |
| `scope.setResponseModel("...")` | `.responseModel("...")` |
| `scope.setTokenUsage(input:output:)` | `.tokens(input:output:)` |
| `scope.setAttributes([:])` | `.attribute(.init("key"), value)` |

## Setup mapping

| v1 | v2 |
| --- | --- |
| `try Terra.start(...)` | `try await Terra.enable(...)` |
| `try Terra.start(config)` | `try await Terra.configure(.init(config))` |
