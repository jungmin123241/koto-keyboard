import Foundation

@MainActor
public protocol TextDocument: AnyObject {
    var before: String? { get }
    var after: String? { get }
    var selected: String? { get }
    var identifier: UUID { get }
    func deleteBackward()
    func insertText(_ text: String)
}

public struct DocumentSnapshot: Equatable {
    public let before: String?
    public let after: String?
    public let identifier: UUID
    public let selected: String?

    @MainActor public init(_ document: any TextDocument) {
        before = document.before
        after = document.after
        identifier = document.identifier
        selected = document.selected
    }

    @MainActor public func matches(_ document: any TextDocument) -> Bool {
        identifier == document.identifier && Self.exact(before, document.before)
        && Self.exact(after, document.after) && Self.exact(selected, document.selected)
    }

    public static func exact(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (left?, right?): return left.utf16.elementsEqual(right.utf16)
        default: return false
        }
    }
}

public enum EditOutcome: Equatable { case replaced, insertedOnly, rejected, interrupted }

@MainActor
public enum DeletionStrategy {
    public static func canReplace(source: String, snapshot: DocumentSnapshot, document: any TextDocument) -> Bool {
        guard !source.isEmpty, source.count <= 500, snapshot.matches(document),
              (document.selected ?? "").isEmpty, let before = document.before,
              before.utf16.count >= source.utf16.count,
              before.utf16.suffix(source.utf16.count).elementsEqual(source.utf16),
              before.count >= source.count,
              DocumentSnapshot.exact(String(before.suffix(source.count)), source) else { return false }
        // Multi-scalar graphemes have host-dependent deletion behavior. Never guess.
        return source.allSatisfy { $0.unicodeScalars.count == 1 }
    }

    public static func apply(source: String, replacement: String, snapshot: DocumentSnapshot,
                             document: any TextDocument, allowInsertionOnly: Bool) -> EditOutcome {
        guard snapshot.matches(document), (document.selected ?? "").isEmpty else { return .rejected }
        guard canReplace(source: source, snapshot: snapshot, document: document) else {
            guard allowInsertionOnly else { return .rejected }
            document.insertText(replacement)
            return .insertedOnly
        }
        var expected = document.before!
        for _ in source {
            guard snapshot.identifier == document.identifier,
                  DocumentSnapshot.exact(document.before, expected),
                  DocumentSnapshot.exact(document.after, snapshot.after),
                  (document.selected ?? "").isEmpty else { return .interrupted }
            expected.removeLast()
            document.deleteBackward()
            guard DocumentSnapshot.exact(document.before, expected) else { return .interrupted }
        }
        guard snapshot.identifier == document.identifier,
              DocumentSnapshot.exact(document.after, snapshot.after),
              (document.selected ?? "").isEmpty else { return .interrupted }
        document.insertText(replacement)
        return .replaced
    }
}

/// Contains only text entered during this keyboard session, never a retrieved document.
public struct InputState {
    public private(set) var typed = ""
    public private(set) var version = 0
    public init() {}
    public mutating func reset() { typed = ""; version += 1 }
    public mutating func set(_ value: String) {
        var current = value
        // Keep a just-finished sentence as a candidate until the next sentence starts.
        // Never inspect or translate earlier host-document content.
        let boundaries: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]
        for index in value.indices.reversed() where boundaries.contains(value[index]) {
            let remainder = value[value.index(after: index)...]
            if remainder.contains(where: { !$0.isWhitespace }) {
                current = String(remainder)
                break
            }
        }
        typed = String(current.suffix(500))
        version += 1
    }
    public var candidate: String { typed.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var trailingWhitespace: String { String(typed.reversed().prefix(while: { $0.isWhitespace }).reversed()) }
}
