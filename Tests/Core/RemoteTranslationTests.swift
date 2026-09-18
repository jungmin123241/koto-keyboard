import XCTest
#if canImport(KeyboardCore)
@testable import KeyboardCore
#endif

final class RemoteTranslationTests: XCTestCase {
    func testInsecureOrCredentialBearingEndpointsAreRejectedBeforeNetworking() async {
        for endpoint in ["http://example.com/v1/translate", "https://user:password@example.com/v1/translate",
                         "https://example.com/v1/translate?key=secret", "https://example.com/v1/translate#fragment"] {
            let service = RemoteTranslationService(endpoint: URL(string: endpoint)!, accessToken: "test", wifiOnly: false)
            do {
                _ = try await service.translate(text: "hello", sourceLanguage: nil, targetLanguage: "ja")
                XCTFail("Invalid endpoint must fail before a network request")
            } catch { XCTAssertEqual(error as? TranslationError, .configuration) }
        }
    }
    func testMissingTokenRejectedBeforeNetworking() async {
        let service = RemoteTranslationService(endpoint: URL(string: "https://example.com/v1/translate")!, accessToken: "", wifiOnly: true)
        do {
            _ = try await service.translate(text: "hello", sourceLanguage: nil, targetLanguage: "ja")
            XCTFail("Missing token must fail")
        } catch { XCTAssertEqual(error as? TranslationError, .configuration) }
    }
    func testMockGreetingAndCancellation() async throws {
        let service = MockTranslationService()
        let result = try await service.translate(text: "안녕하세요", sourceLanguage: nil, targetLanguage: "ja")
        XCTAssertEqual(result.translatedText, "こんにちは")
        let task = Task { try await service.translate(text: "hello", sourceLanguage: nil, targetLanguage: "ja") }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled task must not return a result") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
