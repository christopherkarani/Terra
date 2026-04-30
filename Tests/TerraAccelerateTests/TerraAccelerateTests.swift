import OpenTelemetryApi
import Testing
@testable import TerraAccelerate

@Suite("TerraAccelerate attributes", .serialized)
struct TerraAccelerateTests {
  @Test("attributes use stable keys")
  func attributesUseStableKeys() {
    let attrs = TerraAccelerate.attributes(
      backend: "accelerate",
      operation: "matmul",
      durationMS: 3.5
    )

    #expect(attrs[TerraAccelerate.Keys.backend] == AttributeValue.string("accelerate"))
    #expect(attrs[TerraAccelerate.Keys.operation] == AttributeValue.string("matmul"))
    #expect(attrs[TerraAccelerate.Keys.durationMS] == AttributeValue.double(3.5))
  }
}
