import Foundation

extension Message {
    /// The web links in the message's text, in order, without duplicates.
    var linkURLs: [URL] {
        guard let text = visibleText else { return [] }
        var seen: Set<URL> = []
        return text.matches(of: /https?:\/\/[^\s<>"]+/).compactMap { match in
            // Sentence punctuation and closing brackets usually end the
            // sentence around a link, not the link itself.
            var link = Substring(match.output)
            while let last = link.last, ".,;:!?)]}'*_~".contains(last) {
                link = link.dropLast()
            }
            guard let url = URL(string: String(link)), url.host() != nil, seen.insert(url).inserted else { return nil }
            return url
        }
    }
}
