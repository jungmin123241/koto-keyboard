import XCTest
#if canImport(KeyboardCore)
@testable import KeyboardCore
#endif

final class HangulComposerTests: XCTestCase {
    private func compose(_ keys: String) -> String {
        var composer = HangulComposer()
        for key in keys { composer.append(key) }
        return composer.text
    }
    func testGreeting() { XCTAssertEqual(compose("ㅇㅏㄴㄴㅕㅇㅎㅏㅅㅔㅇㅛ"), "안녕하세요") }
    func testGreetingBuildsAsComposedTextAtEveryKeystroke() {
        var composer = HangulComposer()
        let expected = ["ㅇ", "아", "안", "안ㄴ", "안녀", "안녕"]
        for (key, value) in zip("ㅇㅏㄴㄴㅕㅇ", expected) {
            composer.append(key)
            XCTAssertEqual(composer.text, value)
        }
    }
    func testThanks() { XCTAssertEqual(compose("ㄱㅏㅁㅅㅏㅎㅏㅂㄴㅣㄷㅏ"), "감사합니다") }
    func testCompoundVowels() {
        XCTAssertEqual(compose("ㄱㅗㅏ"), "과")
        XCTAssertEqual(compose("ㄱㅜㅓㄴ"), "권")
        XCTAssertEqual(compose("ㅇㅡㅣ"), "의")
    }
    func testCompoundFinalAndResyllabification() {
        XCTAssertEqual(compose("ㄷㅏㄹㄱ"), "닭")
        XCTAssertEqual(compose("ㄷㅏㄹㄱㅏ"), "달가")
        XCTAssertEqual(compose("ㄱㅏㄴㅏ"), "가나")
        XCTAssertEqual(compose("ㅇㅓㅂㅅㅇㅓ"), "없어")
    }
    func testTenseConsonantsAndStandaloneJamo() {
        XCTAssertEqual(compose("ㄲㅏ"), "까")
        XCTAssertEqual(compose("ㅃㅏㄹㄹㅣ"), "빨리")
        XCTAssertEqual(compose("ㄱㄴㅏ"), "ㄱ나")
    }
    func testBackspaceReversesPhysicalJamoKeys() {
        var composer = HangulComposer()
        for key in "ㄷㅏㄹㄱㅏ" { composer.append(key) }
        for expected in ["닭", "달", "다", "ㄷ", ""] {
            composer.backspace(); XCTAssertEqual(composer.text, expected)
        }
        composer.backspace(); XCTAssertEqual(composer.text, "")
    }
    func testResetDoesNotRetainPreviousWord() {
        var composer = HangulComposer()
        composer.append("ㄱ"); composer.reset(); composer.append("ㄴ")
        XCTAssertEqual(composer.text, "ㄴ")
    }
}
