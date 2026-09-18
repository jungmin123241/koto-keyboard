import Foundation

/// Replays only the active composing run. Backspace removes one physical jamo key.
/// The host adapter replaces the changed suffix, never the entire document.
public struct HangulComposer {
    private var keys: [Character] = []
    public var text: String { Self.render(keys) }
    public var isEmpty: Bool { keys.isEmpty }
    public init() {}
    public mutating func reset() { keys.removeAll(keepingCapacity: false) }
    public mutating func append(_ key: Character) { keys.append(key) }
    public mutating func backspace() { if !keys.isEmpty { keys.removeLast() } }

    private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let finals = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    private static let joinedVowels: [String: Character] = ["ㅗㅏ":"ㅘ", "ㅗㅐ":"ㅙ", "ㅗㅣ":"ㅚ", "ㅜㅓ":"ㅝ", "ㅜㅔ":"ㅞ", "ㅜㅣ":"ㅟ", "ㅡㅣ":"ㅢ"]
    private static let joinedFinals: [String: Character] = ["ㄱㅅ":"ㄳ", "ㄴㅈ":"ㄵ", "ㄴㅎ":"ㄶ", "ㄹㄱ":"ㄺ", "ㄹㅁ":"ㄻ", "ㄹㅂ":"ㄼ", "ㄹㅅ":"ㄽ", "ㄹㅌ":"ㄾ", "ㄹㅍ":"ㄿ", "ㄹㅎ":"ㅀ", "ㅂㅅ":"ㅄ"]

    private static func render(_ keys: [Character]) -> String {
        var output = ""
        var initial: Character?
        var vowel: Character?
        var final: Character?
        func current() -> String {
            if let l = initial, let v = vowel,
               let li = initials.firstIndex(of: l), let vi = vowels.firstIndex(of: v) {
                let ti = final.flatMap { finals.firstIndex(of: $0) } ?? 0
                return String(UnicodeScalar(0xAC00 + (li * 21 + vi) * 28 + ti)!)
            }
            return [initial, vowel, final].compactMap { $0 }.map(String.init).joined()
        }
        func flush() {
            output += current()
            initial = nil; vowel = nil; final = nil
        }
        for key in keys {
            if vowels.contains(key) {
                if vowel == nil { vowel = key }
                else if let tail = final {
                    if let pair = joinedFinals.first(where: { $0.value == tail }) {
                        let parts = Array(pair.key)
                        final = parts[0]
                        let next = parts[1]
                        flush()
                        initial = next; vowel = key
                    } else {
                        final = nil
                        flush()
                        initial = tail; vowel = key
                    }
                } else if let v = vowel, let combined = joinedVowels[String(v) + String(key)] {
                    vowel = combined
                } else { flush(); vowel = key }
            } else if initials.contains(key) {
                if initial != nil && vowel != nil {
                    if final == nil && finals.contains(key) { final = key }
                    else if let tail = final, let combined = joinedFinals[String(tail) + String(key)] { final = combined }
                    else { flush(); initial = key }
                } else { flush(); initial = key }
            } else { flush(); output.append(key) }
        }
        return output + current()
    }
}
