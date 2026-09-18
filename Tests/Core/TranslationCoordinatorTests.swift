import XCTest
#if canImport(KeyboardCore)
@testable import KeyboardCore
#endif

private actor RecordingService: TranslationService {
    var calls: [String] = []
    let failure: TranslationError?
    let delayed: Bool
    init(failure: TranslationError? = nil, delayed: Bool = false) { self.failure = failure; self.delayed = delayed }
    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> TranslationResult {
        calls.append(text)
        // Intentionally ignore cancellation to prove stale responses cannot win.
        if delayed { try? await Task.sleep(nanoseconds: text == "old" ? 160_000_000 : 5_000_000) }
        if let failure { throw failure }
        return TranslationResult(originalText: text, translatedText: "訳:" + text, detectedSourceLanguage: nil, provider: "test")
    }
    func count() -> Int { calls.count }
}

final class TranslationCoordinatorTests: XCTestCase {
    @MainActor func testMinimumLengthAndComposingJamo() async {
        for text in ["a", "ㄱ", "안녕ㅎ", "123", "😀"] { XCTAssertFalse(TranslationCoordinator.isEligible(text)) }
        for text in ["나", "私", "hi", "안녕하세요"] { XCTAssertTrue(TranslationCoordinator.isEligible(text)) }
    }
    @MainActor func testWhitespaceAndNonLanguageInputDoNotRequest() async throws {
        let coordinator = TranslationCoordinator(), service = RecordingService()
        for text in ["", " \n ", "123", "😀"] {
            coordinator.request(text: text, target: "ja", contextVersion: 0, delayMilliseconds: 0, service: service)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let count = await service.count()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(coordinator.state, .empty)
    }
    @MainActor func testDebounceCancelsSupersededInput() async throws {
        let coordinator = TranslationCoordinator(), service = RecordingService()
        coordinator.request(text: "he", target: "ja", contextVersion: 1, delayMilliseconds: 80, service: service)
        coordinator.request(text: "hello", target: "ja", contextVersion: 2, delayMilliseconds: 80, service: service)
        try await Task.sleep(nanoseconds: 30_000_000)
        let early = await service.count(); XCTAssertEqual(early, 0)
        try await Task.sleep(nanoseconds: 120_000_000)
        let count = await service.count(); XCTAssertEqual(count, 1)
    }
    @MainActor func testDuplicateRequestIsSuppressed() async throws {
        let coordinator = TranslationCoordinator(), service = RecordingService()
        for _ in 0..<3 { coordinator.request(text: "hello", target: "ja", contextVersion: 1, delayMilliseconds: 0, service: service) }
        try await Task.sleep(nanoseconds: 30_000_000)
        coordinator.request(text: "hello", target: "ja", contextVersion: 1, delayMilliseconds: 0, service: service)
        coordinator.request(text: "hello  ", target: "ja", contextVersion: 2, delayMilliseconds: 0, service: service)
        try await Task.sleep(nanoseconds: 20_000_000)
        let count = await service.count(); XCTAssertEqual(count, 1)
    }
    @MainActor func testLateResponseCannotReplaceNewResult() async throws {
        let coordinator = TranslationCoordinator(), service = RecordingService(delayed: true)
        coordinator.request(text: "old", target: "ja", contextVersion: 1, delayMilliseconds: 0, service: service)
        try await Task.sleep(nanoseconds: 20_000_000)
        coordinator.request(text: "new", target: "ja", contextVersion: 2, delayMilliseconds: 0, service: service)
        try await Task.sleep(nanoseconds: 220_000_000)
        guard case .translated(let result) = coordinator.state else { return XCTFail("Expected newest translation") }
        XCTAssertEqual(result.originalText, "new")
    }
    @MainActor func testResetCancelsResultAndClearsText() async throws {
        let coordinator = TranslationCoordinator(), service = RecordingService(delayed: true)
        coordinator.request(text: "old", target: "ja", contextVersion: 1, delayMilliseconds: 0, service: service)
        try await Task.sleep(nanoseconds: 20_000_000)
        coordinator.reset()
        try await Task.sleep(nanoseconds: 190_000_000)
        XCTAssertEqual(coordinator.state, .idle)
    }
    @MainActor func testFailureAndTimeoutPermitRetry() async throws {
        for error in [TranslationError.server, .timeout, .offline] {
            let coordinator = TranslationCoordinator(), service = RecordingService(failure: error)
            coordinator.request(text: "hello", target: "ja", contextVersion: 1, delayMilliseconds: 0, service: service)
            try await Task.sleep(nanoseconds: 30_000_000)
            XCTAssertEqual(coordinator.state, .failed(error))
            coordinator.request(text: "hello", target: "ja", contextVersion: 1, delayMilliseconds: 0, service: service)
            try await Task.sleep(nanoseconds: 30_000_000)
            let count = await service.count(); XCTAssertEqual(count, 2)
        }
    }
    func testLocalTranslationsAndUnsupportedText() async throws {
        let service = LocalTranslationService()
        for text in ["안녕하세요", "hello", "こんにちは", "你好"] {
            let result = try await service.translate(text: text, sourceLanguage: nil, targetLanguage: "ja")
            XCTAssertEqual(result.translatedText, "こんにちは")
        }
        do { _ = try await service.translate(text: "not a phrasebook entry", sourceLanguage: nil, targetLanguage: "ja"); XCTFail("Must not fabricate a translation") }
        catch { XCTAssertEqual(error as? TranslationError, .unsupported) }
    }
}
