import Testing
@testable import TerraCore

@Suite("Terra.Trace protocol", .serialized)
struct TerraTraceProtocolTests {
  @Test("All trace context types conform to Terra.Trace")
  func traceConformance() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    func assertTrace<T: Terra.Trace>(_ trace: T) {
      _ = trace.event("unit.test")
    }

    _ = try await Terra.inference(model: "trace-model").execute { trace in
      assertTrace(trace)
      return "ok"
    }
    _ = try await Terra.stream(model: "trace-model").execute { trace in
      assertTrace(trace)
      return "ok"
    }
    _ = try await Terra.embedding(model: "trace-model").execute { trace in
      assertTrace(trace)
      return "ok"
    }
    _ = try await Terra.agent(name: "trace-agent").execute { trace in
      assertTrace(trace)
      return "ok"
    }
    _ = try await Terra.tool(name: "trace-tool", callID: "call-1").execute { trace in
      assertTrace(trace)
      return "ok"
    }
    _ = try await Terra.safetyCheck(name: "trace-safety").execute { trace in
      assertTrace(trace)
      return "ok"
    }
  }

  @Test("recordError writes exception telemetry")
  func recordErrorOnTrace() async throws {
    let support = TerraTestSupport()
    Terra.install(.init(tracerProvider: support.tracerProvider, registerProvidersAsGlobal: false))

    enum ExpectedError: Error { case failed }

    _ = try await Terra.inference(model: "trace-model").execute { trace in
      trace.recordError(ExpectedError.failed)
      return "ok"
    }

    let span = try #require(support.finishedSpans().first)
    #expect(span.events.contains { $0.name == "exception" })
    #expect(span.status.isError)
  }

  @Test("recordError omits exception message under redacted privacy")
  func recordErrorOnTraceRespectsPrivacy() async throws {
    let support = TerraTestSupport()
    Terra.install(
      .init(
        privacy: .init(contentPolicy: .optIn, redaction: .hashHMACSHA256),
        tracerProvider: support.tracerProvider,
        registerProvidersAsGlobal: false
      )
    )

    enum ExpectedError: Error, CustomStringConvertible {
      case failed

      var description: String {
        "trace-protocol-secret"
      }
    }

    _ = try await Terra.inference(model: "trace-model").execute { trace in
      trace.recordError(ExpectedError.failed)
      return "ok"
    }

    let span = try #require(support.finishedSpans().first)
    let exception = try #require(span.events.first(where: { $0.name == "exception" }))
    #expect(exception.attributes["exception.type"]?.description == String(reflecting: ExpectedError.self))
    #expect(exception.attributes["exception.message"] == nil)
  }
}
