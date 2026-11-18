import Foundation

extension ComposerMarkdownEdit {
    /// Wraps the selection in `width` of `marker`, or unwraps it when it's
    /// already wrapped, just outside or just inside. A selection over
    /// several lines is wrapped line by line, since emphasis can't cross
    /// list items or paragraphs. With nothing selected, it adds an empty
    /// pair to type into, or removes the empty pair the caret is in.
    static func toggleInline(_ marker: UInt16, width: Int, in chars: [UInt16], selection: NSRange) -> ComposerMarkdownEdit {
        let markup = String(decoding: [UInt16](repeating: marker, count: width), as: UTF16.self)
        // `***` is both bold and italic.
        func hasMarkup(_ run: Int) -> Bool {
            run == width || (marker == .asterisk && run == 3)
        }

        if selection.length == 0 {
            let caret = selection.location
            if hasMarkup(run(of: marker, endingAt: caret, in: chars)), hasMarkup(run(of: marker, startingAt: caret, in: chars)) {
                return ComposerMarkdownEdit(
                    replacements: [
                        Replacement(range: NSRange(location: caret, length: width), text: ""),
                        Replacement(range: NSRange(location: caret - width, length: width), text: ""),
                    ],
                    selection: NSRange(location: caret - width, length: 0)
                )
            }
            return ComposerMarkdownEdit(
                replacements: [Replacement(range: selection, text: markup + markup)],
                selection: NSRange(location: caret + width, length: 0)
            )
        }

        let pieces = inlinePieces(of: selection, in: chars)
        guard !pieces.isEmpty else { return ComposerMarkdownEdit(replacements: [], selection: selection) }
        enum State { case wrappedOutside, wrappedInside, plain }
        let states: [State] = pieces.map { piece in
            if hasMarkup(run(of: marker, endingAt: piece.location, in: chars)),
               hasMarkup(run(of: marker, startingAt: NSMaxRange(piece), in: chars)) {
                return .wrappedOutside
            }
            let leading = min(run(of: marker, startingAt: piece.location, in: chars), piece.length)
            let trailing = min(run(of: marker, endingAt: NSMaxRange(piece), in: chars), piece.length)
            if piece.length > 2 * width, hasMarkup(leading), hasMarkup(trailing) {
                return .wrappedInside
            }
            return .plain
        }

        var replacements: [Replacement] = []
        let unwraps = !states.contains(.plain)
        for (piece, state) in zip(pieces, states) {
            switch (unwraps, state) {
            case (true, .wrappedOutside):
                replacements.append(Replacement(range: NSRange(location: piece.location - width, length: width), text: ""))
                replacements.append(Replacement(range: NSRange(location: NSMaxRange(piece), length: width), text: ""))
            case (true, .wrappedInside):
                replacements.append(Replacement(range: NSRange(location: piece.location, length: width), text: ""))
                replacements.append(Replacement(range: NSRange(location: NSMaxRange(piece) - width, length: width), text: ""))
            case (false, .plain):
                replacements.append(Replacement(range: NSRange(location: NSMaxRange(piece), length: 0), text: markup))
                replacements.append(Replacement(range: NSRange(location: piece.location, length: 0), text: markup))
            default:
                break
            }
        }
        let start = map(pieces[0].location, through: replacements, followsInsertions: true)
        let end = map(NSMaxRange(pieces[pieces.count - 1]), through: replacements, followsInsertions: false)
        return ComposerMarkdownEdit(replacements: replacements, selection: NSRange(location: start, length: max(end - start, 0)))
    }

    /// The selected text of each line, after the line's quote or list
    /// markers and without surrounding spaces, which emphasis can't have
    /// inside its markers.
    private static func inlinePieces(of selection: NSRange, in chars: [UInt16]) -> [NSRange] {
        var pieces: [NSRange] = []
        var location = selection.location
        let end = NSMaxRange(selection)
        while location < end {
            let line = ComposerMarkdownLine.line(in: chars, containing: location)
            var start = max(location, line.contentStart)
            var pieceEnd = min(end, line.end)
            while start < pieceEnd, chars[start].isMarkdownWhitespace { start += 1 }
            while pieceEnd > start, chars[pieceEnd - 1].isMarkdownWhitespace { pieceEnd -= 1 }
            if pieceEnd > start { pieces.append(NSRange(location: start, length: pieceEnd - start)) }
            location = line.end + 1
        }
        return pieces
    }

    static func run(of marker: UInt16, endingAt location: Int, in chars: [UInt16]) -> Int {
        var start = location
        while start > 0, chars[start - 1] == marker { start -= 1 }
        return location - start
    }

    static func run(of marker: UInt16, startingAt location: Int, in chars: [UInt16]) -> Int {
        var end = location
        while end < chars.count, chars[end] == marker { end += 1 }
        return end - location
    }

    /// Makes the selection a link's label, or its URL when it is one, with
    /// the caret where the missing half goes.
    static func link(in chars: [UInt16], selection: NSRange) -> ComposerMarkdownEdit {
        let start = selection.location
        let end = NSMaxRange(selection)
        if selection.length > 0, isURL(string(chars, selection)) {
            return ComposerMarkdownEdit(
                replacements: [
                    Replacement(range: NSRange(location: end, length: 0), text: ")"),
                    Replacement(range: NSRange(location: start, length: 0), text: "[]("),
                ],
                selection: NSRange(location: start + 1, length: 0)
            )
        }
        return ComposerMarkdownEdit(
            replacements: [
                Replacement(range: NSRange(location: end, length: 0), text: "]()"),
                Replacement(range: NSRange(location: start, length: 0), text: "["),
            ],
            selection: NSRange(location: end + 3, length: 0)
        )
    }

    /// Pasting a URL over selected text links the text to it, as Slack does.
    static func pastingLink(_ url: String, in text: String, selection: NSRange) -> ComposerMarkdownEdit? {
        let chars = Array(text.utf16)
        guard selection.length > 0, NSMaxRange(selection) <= chars.count, isURL(url) else { return nil }
        let label = string(chars, selection)
        guard !isURL(label), !label.contains("\n") else { return nil }
        let end = NSMaxRange(selection)
        let destination = "](\(url))"
        return ComposerMarkdownEdit(
            replacements: [
                Replacement(range: NSRange(location: end, length: 0), text: destination),
                Replacement(range: NSRange(location: selection.location, length: 0), text: "["),
            ],
            selection: NSRange(location: end + 1 + destination.utf16.count, length: 0)
        )
    }

    /// A single web or mail address, with nothing around it.
    static func isURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme) && (scheme == "mailto" || url.host() != nil)
    }
}
