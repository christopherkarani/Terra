import Testing
@testable import TerraCore

@Suite("Privacy V3", .serialized)
struct TerraPrivacyV3TopLevelTests {
@Test("Privacy enum has four cases")
func privacyEnumCases() {
  let policies: [Terra.PrivacyPolicy] = [.redacted, .lengthOnly, .capturing, .silent]
  #expect(policies.count == 4)
}

@Test("Privacy.shouldCapture returns correct values")
func shouldCaptureLogic() {
  #expect(Terra.PrivacyPolicy.redacted.shouldCapture == false)
  #expect(Terra.PrivacyPolicy.lengthOnly.shouldCapture == false)
  #expect(Terra.PrivacyPolicy.capturing.shouldCapture == true)
  #expect(Terra.PrivacyPolicy.silent.shouldCapture == false)
}

@Test("Privacy.shouldCapture with includeContent override")
func includeContentOverride() {
  #expect(Terra.PrivacyPolicy.redacted.shouldCapture(includeContent: true) == true)
  #expect(Terra.PrivacyPolicy.silent.shouldCapture(includeContent: true) == false)
}

@Test("Privacy.redactionStrategy mapping")
func redactionStrategyMapping() {
  #expect(Terra.PrivacyPolicy.redacted.redactionStrategy == .hashHMACSHA256)
  #expect(Terra.PrivacyPolicy.lengthOnly.redactionStrategy == .lengthOnly)
  #expect(Terra.PrivacyPolicy.capturing.redactionStrategy == .hashHMACSHA256)
  #expect(Terra.PrivacyPolicy.silent.redactionStrategy == .drop)
}
}
