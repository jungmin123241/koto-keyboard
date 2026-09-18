import Foundation

enum KeyboardLayout {
    static func rows(korean: Bool, shifted: Bool, symbols: Bool) -> [[String]] {
        if symbols {
            return [Array("1234567890").map(String.init), Array("@#₩%&*()-").map(String.init), Array(".,?!'\"/:;").map(String.init)]
        }
        if korean {
            return [Array(shifted ? "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ" : "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ").map(String.init),
                    Array("ㅁㄴㅇㄹㅎㅗㅓㅏㅣ").map(String.init), Array("ㅋㅌㅊㅍㅠㅜㅡ").map(String.init)]
        }
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        return rows.map { Array(shifted ? $0.uppercased() : $0).map(String.init) }
    }
}
