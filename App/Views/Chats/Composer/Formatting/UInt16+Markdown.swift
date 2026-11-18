import Foundation

/// UTF-16 code units the composer's Markdown parsing looks for.
extension UInt16 {
    static let newline = UInt16(UInt8(ascii: "\n"))
    static let space = UInt16(UInt8(ascii: " "))
    static let tab = UInt16(UInt8(ascii: "\t"))
    static let greaterThan = UInt16(UInt8(ascii: ">"))
    static let hyphen = UInt16(UInt8(ascii: "-"))
    static let asterisk = UInt16(UInt8(ascii: "*"))
    static let plus = UInt16(UInt8(ascii: "+"))
    static let underscore = UInt16(UInt8(ascii: "_"))
    static let tilde = UInt16(UInt8(ascii: "~"))
    static let backtick = UInt16(UInt8(ascii: "`"))
    static let backslash = UInt16(UInt8(ascii: "\\"))
    static let period = UInt16(UInt8(ascii: "."))
    static let closingParenthesis = UInt16(UInt8(ascii: ")"))
    static let openingParenthesis = UInt16(UInt8(ascii: "("))
    static let openingBracket = UInt16(UInt8(ascii: "["))
    static let closingBracket = UInt16(UInt8(ascii: "]"))
    static let hash = UInt16(UInt8(ascii: "#"))
    static let equals = UInt16(UInt8(ascii: "="))
    static let letterA = UInt16(UInt8(ascii: "a"))

    /// The digit's value, for an ASCII digit.
    var asciiDigit: Int? {
        (48...57).contains(self) ? Int(self) - 48 : nil
    }

    var isMarkdownWhitespace: Bool {
        self == .space || self == .tab || self == .newline || self == 0x0D || self == 0x0C || self == 0x0B || self == 0xA0
            || (0x2000...0x200A).contains(self) || self == 0x3000
    }

    /// ASCII punctuation, plus the general Unicode punctuation block, which
    /// covers the curly quotes and dashes chat text uses.
    var isMarkdownPunctuation: Bool {
        (33...47).contains(self) || (58...64).contains(self) || (91...96).contains(self) || (123...126).contains(self)
            || (0x2010...0x2027).contains(self) || (0x2030...0x205E).contains(self) || (0x3001...0x3003).contains(self)
    }

    var isASCIIPunctuation: Bool {
        (33...47).contains(self) || (58...64).contains(self) || (91...96).contains(self) || (123...126).contains(self)
    }
}
