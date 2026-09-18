import XCTest
#if canImport(KeyboardCore)
@testable import KeyboardCore
#endif

@MainActor
private final class FakeDocument: TextDocument {
    var before: String?
    var after: String? = ""
    var selected: String?
    var identifier = UUID()
    var deletes = 0
    var inserts = 0
    var changeDuringDeletion = false
    init(_ text: String?) { before = text }
    func deleteBackward() {
        deletes += 1
        if var value = before, !value.isEmpty { value.removeLast(); before = value }
        if changeDuringDeletion { before = "external edit" }
    }
    func insertText(_ text: String) { before = (before ?? "") + text; inserts += 1 }
}

final class DocumentEditingTests: XCTestCase {
    @MainActor func testReplacesOnlyVerifiedSuffix() async {
        let document = FakeDocument("앞 문장. 안녕하세요")
        let snapshot = DocumentSnapshot(document)
        XCTAssertEqual(DeletionStrategy.apply(source: "안녕하세요", replacement: "こんにちは", snapshot: snapshot, document: document, allowInsertionOnly: true), .replaced)
        XCTAssertEqual(document.before, "앞 문장. こんにちは")
        XCTAssertEqual(document.deletes, 5)
        XCTAssertEqual(DeletionStrategy.apply(source: "안녕하세요", replacement: "こんにちは", snapshot: snapshot, document: document, allowInsertionOnly: true), .rejected)
        XCTAssertEqual(document.deletes, 5)
    }
    @MainActor func testUTF16LengthIsNotDeletionCount() async {
        let document = FakeDocument("A😀")
        XCTAssertEqual("😀".utf16.count, 2)
        XCTAssertEqual(DeletionStrategy.apply(source: "😀", replacement: "笑", snapshot: DocumentSnapshot(document), document: document, allowInsertionOnly: true), .replaced)
        XCTAssertEqual(document.deletes, 1)
        XCTAssertEqual(document.before, "A笑")
    }
    @MainActor func testCombiningCharactersAndEmojiSequencesUseInsertionOnly() async {
        for source in ["e\u{301}", "👨‍👩‍👧‍👦", "가", "🇰🇷"] {
            let document = FakeDocument(source)
            XCTAssertEqual(DeletionStrategy.apply(source: source, replacement: "訳", snapshot: DocumentSnapshot(document), document: document, allowInsertionOnly: true), .insertedOnly)
            XCTAssertEqual(document.deletes, 0)
            XCTAssertEqual(document.before, source + "訳")
        }
    }
    @MainActor func testMissingContextDoesNotDelete() async {
        let document = FakeDocument(nil)
        XCTAssertEqual(DeletionStrategy.apply(source: "hello", replacement: "こんにちは", snapshot: DocumentSnapshot(document), document: document, allowInsertionOnly: true), .insertedOnly)
        XCTAssertEqual(document.deletes, 0)
    }
    @MainActor func testChangedCursorOrDocumentRejectsCandidate() async {
        let document = FakeDocument("hello")
        let snapshot = DocumentSnapshot(document)
        document.after = "other text"
        XCTAssertEqual(DeletionStrategy.apply(source: "hello", replacement: "こんにちは", snapshot: snapshot, document: document, allowInsertionOnly: true), .rejected)
        document.after = ""; document.identifier = UUID()
        XCTAssertEqual(DeletionStrategy.apply(source: "hello", replacement: "こんにちは", snapshot: snapshot, document: document, allowInsertionOnly: true), .rejected)
        XCTAssertEqual(document.deletes, 0)
        XCTAssertEqual(document.inserts, 0)
    }
    @MainActor func testSelectionCannotBeReplacedByStaleCandidate() async {
        let document = FakeDocument("hello")
        document.selected = "selected text"
        XCTAssertEqual(DeletionStrategy.apply(source: "hello", replacement: "こんにちは", snapshot: DocumentSnapshot(document), document: document, allowInsertionOnly: true), .rejected)
        XCTAssertEqual(document.inserts, 0)
    }
    @MainActor func testUnexpectedDeletionStopsImmediately() async {
        let document = FakeDocument("hello")
        document.changeDuringDeletion = true
        XCTAssertEqual(DeletionStrategy.apply(source: "hello", replacement: "こんにちは", snapshot: DocumentSnapshot(document), document: document, allowInsertionOnly: true), .interrupted)
        XCTAssertEqual(document.deletes, 1)
        XCTAssertEqual(document.inserts, 0)
    }
    func testCanonicalEqualityIsNotSufficientForReplacement() {
        XCTAssertEqual("é", "e\u{301}")
        XCTAssertFalse(DocumentSnapshot.exact("é", "e\u{301}"))
    }
    func testInputStateBoundsTextAndPreservesTrailingSpace() {
        var input = InputState()
        input.set("안녕하세요  ")
        XCTAssertEqual(input.candidate, "안녕하세요")
        XCTAssertEqual(input.trailingWhitespace, "  ")
        input.set(String(repeating: "가", count: 600))
        XCTAssertEqual(input.typed.count, 500)
        input.reset(); XCTAssertEqual(input.candidate, "")
    }
    func testOnlyCurrentSentenceIsEligible() {
        var input = InputState()
        input.set("첫 문장. ")
        XCTAssertEqual(input.candidate, "첫 문장.")
        input.set("첫 문장. 다음 문장")
        XCTAssertEqual(input.candidate, "다음 문장")
        input.set("前の文。次の文")
        XCTAssertEqual(input.candidate, "次の文")
    }
}
