#ifndef TERRA_LLAMA_HOOKS_H
#define TERRA_LLAMA_HOOKS_H

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef uint64_t TerraLlamaSpanHandle;

typedef enum TerraLlamaCallbackStage {
  TERRA_LLAMA_STAGE_MODEL_LOAD = 0,
  TERRA_LLAMA_STAGE_PROMPT_EVAL = 1,
  TERRA_LLAMA_STAGE_DECODE = 2,
  TERRA_LLAMA_STAGE_STREAM_LIFECYCLE = 3,
  TERRA_LLAMA_STAGE_FINISH = 4
} TerraLlamaCallbackStage;

void terra_llama_record_token_event(
  TerraLlamaSpanHandle handle,
  uint64_t token_index,
  double decode_latency_ms,
  double log_probability,
  double kv_cache_usage_percent
);

void terra_llama_record_stage_event(
  TerraLlamaSpanHandle handle,
  int32_t stage,
  uint64_t token_count,
  double duration_ms
);

void terra_llama_record_stall_event(
  TerraLlamaSpanHandle handle,
  double gap_ms,
  double threshold_ms,
  double baseline_p95_ms
);

void terra_llama_finish_stream(TerraLlamaSpanHandle handle);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif /* TERRA_LLAMA_HOOKS_H */
