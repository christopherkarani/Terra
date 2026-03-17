/*
 * basic.cpp — Terra C++ SDK usage example
 *
 * Build:
 *   cd terra-cpp && cmake -B build && cmake --build build
 *   ./build/basic
 */

#include "terra.hpp"
#include <cstdio>
#include <cstdlib>

int main() {
    try {
        // Print library version
        auto ver = terra::Instance::version();
        std::printf("Terra v%u.%u.%u\n", ver.major, ver.minor, ver.patch);

        // Initialize with defaults
        auto inst = terra::Instance::init();
        std::printf("Running: %s\n", inst.is_running() ? "yes" : "no");

        // Set service metadata
        inst.set_service_info("my-app", "1.0.0");
        inst.set_session_id("session-001");

        // Simple inference span (RAII)
        {
            auto span = inst.begin_inference("gpt-4");
            span.set("gen_ai.request.max_tokens", 1024);
            span.set("gen_ai.request.temperature", 0.7);
            span.set("gen_ai.request.stream", false);
            span.add_event("inference.started");

            // ... do inference work ...

            span.set("gen_ai.response.model", "gpt-4-0613");
            span.set("gen_ai.usage.input_tokens", static_cast<int64_t>(150));
            span.set("gen_ai.usage.output_tokens", static_cast<int64_t>(42));
            span.set_status(terra::StatusCode::Ok);
            // span.end() called by destructor
        }

        // Streaming span
        {
            auto stream = inst.begin_streaming("llama-3.1-8b");
            stream.set("gen_ai.request.max_tokens", 2048);

            // Simulate streaming tokens
            stream.record_first_token();
            for (int i = 0; i < 10; ++i) {
                stream.record_token();
            }
            stream.finish_stream();
            // end() called by destructor
        }

        // Nested agent -> tool spans using parent context
        {
            auto agent = inst.begin_agent("research-agent");
            auto agent_ctx = agent.context();

            {
                auto tool = inst.begin_tool("web-search", &agent_ctx);
                tool.set("terra.tool.input", "latest AI papers");
                tool.set_status(terra::StatusCode::Ok);
            }

            {
                auto tool = inst.begin_tool("summarizer", &agent_ctx);
                tool.record_error("TimeoutError", "summarization timed out");
                // record_error sets status to Error by default
            }

            agent.set_status(terra::StatusCode::Ok);
        }

        // Embedding span
        {
            auto embed = inst.begin_embedding("text-embedding-3-small");
            embed.set("gen_ai.usage.input_tokens", static_cast<int64_t>(512));
            embed.set_status(terra::StatusCode::Ok);
        }

        // Safety check span
        {
            auto safety = inst.begin_safety("content-filter");
            safety.set("terra.safety.passed", true);
            safety.set_status(terra::StatusCode::Ok);
        }

        // Record standalone metrics
        inst.record_inference_duration(142.5);
        inst.record_token_count(150, 42);

        // Diagnostics
        std::printf("Spans dropped: %llu\n",
                    static_cast<unsigned long long>(inst.spans_dropped()));
        std::printf("Transport degraded: %s\n",
                    inst.transport_degraded() ? "yes" : "no");

        // Shutdown (also called by destructor)
        inst.shutdown();
        std::printf("Shut down cleanly.\n");

    } catch (const terra::Error& e) {
        std::fprintf(stderr, "Terra error (code %d): %s\n", e.code(), e.what());
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
