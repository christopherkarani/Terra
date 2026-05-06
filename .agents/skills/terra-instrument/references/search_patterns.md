# Codebase Scan Patterns

Use these patterns to identify all AI telemetry hotspots in a codebase. Run each category and collect matches.

---

## 1. HTTP AI API Calls

Cloud-hosted LLM inference via HTTP. Auto-instrumented by `Terra.start()` for the 8 default hosts.

**Grep patterns:**
```
api.openai.com
api.anthropic.com
generativelanguage.googleapis.com
api.together.xyz
api.mistral.ai
api.groq.com
api.cohere.com
api.fireworks.ai
/v1/chat/completions
/v1/completions
/v1/embeddings
/v1/messages
generateContent
streamGenerateContent
```

**Glob patterns:**
```
**/*OpenAI*.swift
**/*Anthropic*.swift
**/*ChatGPT*.swift
**/*LLM*.swift
**/*AIService*.swift
**/*AIClient*.swift
```

**Tier:** 1 (auto-instrumented) for default hosts. Tier 2 (manual span) for custom/self-hosted endpoints.

---

## 2. CoreML Models

On-device ML inference via Apple CoreML. Auto-instrumented by `Terra.start()`.

**Grep patterns:**
```
MLModel
\.prediction\(
\.predictions\(
MLModelConfiguration
compileModel
\.mlmodel
\.mlpackage
MLMultiArray
MLFeatureProvider
```

**Glob patterns:**
```
**/*.mlmodel
**/*.mlpackage
**/*.mlmodelc
**/*CoreML*.swift
**/*MLModel*.swift
```

**Tier:** 1 (auto-instrumented via ObjC swizzling on MLModel.prediction).

---

## 3. Apple Foundation Models

On-device Apple Intelligence (macOS 26+, iOS 26+).

**Grep patterns:**
```
import FoundationModels
LanguageModelSession
SystemLanguageModel
@Generable
streamResponse
\.respond\(to:
```

**Glob patterns:**
```
**/*FoundationModel*.swift
**/*LanguageModel*.swift
**/*AppleAI*.swift
**/*Intelligence*.swift
```

**Tier:** 3 — Replace `LanguageModelSession` with `TerraTracedSession` (aliased as `Terra.TracedSession`).

---

## 4. MLX-Swift

On-device inference via Apple MLX framework.

**Grep patterns:**
```
import MLX
import MLXLLM
import MLXRandom
MLXModelContainer
MLXModel
generate\(.*prompt
loadModel
```

**Glob patterns:**
```
**/*MLX*.swift
**/*mlx*.swift
```

**Tier:** 3 — Wrap generation in `TerraMLX.traced(model:)`.

---

## 5. llama.cpp / LlamaSwift

On-device inference via llama.cpp C bindings.

**Grep patterns:**
```
import Llama
llama_context
llama_model
LlamaModel
LlamaContext
llama_decode
llama_batch
llama_token
```

**Glob patterns:**
```
**/*Llama*.swift
**/*llama*.swift
**/*GGUF*.swift
```

**Tier:** 3 — Wrap in `TerraLlama.traced(model:prompt:)`.

---

## 6. Local Inference Servers

Ollama, LM Studio, and other local servers. NOT in default hosts — need manual config.

**Grep patterns:**
```
localhost:11434
127.0.0.1:11434
localhost:1234
127.0.0.1:1234
localhost:8080/v1
ollama
lmstudio
LocalAI
```

**Glob patterns:**
```
**/*Ollama*.swift
**/*LMStudio*.swift
**/*LocalAI*.swift
```

**Tier:** 2 — Either add host to `aiAPIHosts` in `AutoInstrumentConfiguration`, or wrap with manual `withInferenceSpan`.

---

## 7. Agent / Orchestration Loops

Multi-step AI workflows with planning, reasoning, or decision loops.

**Grep patterns:**
```
agent
orchestrat
planning
reasoning
step.*loop
think.*act
react.*pattern
chain.*thought
multi.*turn
conversation.*loop
run.*agent
invoke.*agent
```

**Glob patterns:**
```
**/*Agent*.swift
**/*Orchestrat*.swift
**/*Pipeline*.swift
**/*Chain*.swift
**/*Workflow*.swift
```

**Tier:** 2 — Wrap outer loop with `withAgentInvocationSpan`, nest child spans inside.

---

## 8. Tool / Function Calling

AI function calling and tool use.

**Grep patterns:**
```
tool_call
function_call
tool.*execution
tool.*invoke
tool.*use
functionCall
toolCall
ToolDefinition
FunctionDefinition
```

**Glob patterns:**
```
**/*Tool*.swift
**/*Function*.swift
**/*Action*.swift
```

**Tier:** 2 — Wrap each tool execution with `withToolExecutionSpan`.

---

## 9. Embeddings

Vector embeddings for search, RAG, similarity.

**Grep patterns:**
```
embedding
NLEmbedding
vector.*search
similarity.*search
cosine.*similarity
semantic.*search
/v1/embeddings
embed.*model
```

**Glob patterns:**
```
**/*Embedding*.swift
**/*Vector*.swift
**/*Semantic*.swift
**/*RAG*.swift
```

**Tier:** 2 — Wrap with `withEmbeddingSpan`.

---

## 10. Safety / Moderation Checks

Content filtering, toxicity detection, guardrails.

**Grep patterns:**
```
moderat
content.*filter
safety.*check
toxicity
guardrail
harm.*detect
nsfw
content.*policy
```

**Glob patterns:**
```
**/*Safety*.swift
**/*Moderat*.swift
**/*Filter*.swift
**/*Guard*.swift
```

**Tier:** 2 — Wrap with `withSafetyCheckSpan`.

---

## 11. Streaming Responses

Streaming token delivery via SSE or AsyncSequence.

**Grep patterns:**
```
AsyncSequence
AsyncThrowingStream
for.*await.*in
text/event-stream
data:.*\[DONE\]
SSE
streamCompletion
streamResponse
chunk
```

**Glob patterns:**
```
**/*Stream*.swift
**/*SSE*.swift
**/*EventSource*.swift
```

**Tier:** 2 — Use `withStreamingInferenceSpan` with `recordToken()` / `recordChunk()`.

---

## Scan Execution Order

1. Run ALL grep patterns across `**/*.swift` files
2. Run ALL glob patterns to find relevant files
3. Deduplicate results
4. Classify each match into Tier 1, 2, or 3
5. Report summary: `N hotspots found (X auto-instrumented, Y need manual spans, Z need framework wrappers)`
