#ifndef TERRA_LLAMA_HOOKS_H
#define TERRA_LLAMA_HOOKS_H

#include <stdint.h>

typedef struct TerraLlamaTokenEvent {
  uint64_t token_index;
  double decode_latency_ms;
  double log_probability;
  double kv_cache_usage_percent;
} TerraLlamaTokenEvent;

typedef void (*TerraLlamaTokenCallback)(const TerraLlamaTokenEvent *event, void *context);

typedef struct TerraLlamaCallbackRegistration {
  TerraLlamaTokenCallback callback;
  void *context;
} TerraLlamaCallbackRegistration;

#endif /* TERRA_LLAMA_HOOKS_H */
