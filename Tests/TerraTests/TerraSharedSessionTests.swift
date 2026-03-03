import Testing
@testable import TerraCore

@Suite("Terra.shared()", .serialized)
struct TerraSharedSessionTests {
  @Test("shared() returns a session without throwing")
  func test_shared_returns_session_without_throwing() async {
    let session = await Terra.shared()
    #expect(session is Terra.Session)
  }
}
