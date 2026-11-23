#if DEBUG
import Foundation
#if os(iOS)
import UIKit
#endif

/// The chats the timeline lab opens.
enum TimelineLabFixture: String, CaseIterable, Identifiable {
    /// Three messages, well inside the view.
    case short
    /// Just short of the view, so it stops fitting once the keyboard is up.
    case nearlyFull
    /// Many messages of similar height.
    case long
    /// Many messages from one line to dozens, which the lazy stack estimates badly.
    case uneven
    /// Text from one line to dozens mixed with photos of varied shapes,
    /// which load after their rows are first laid out.
    case media

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static func messages(for fixture: TimelineLabFixture, chatID: String) -> [Message] {
        let seed = UInt64(allCases.firstIndex(of: fixture) ?? 0) + 1
        var generator = TimelineLabRandom(seed: seed &* 0x9E37_79B9_7F4A_7C15)
        let wordCounts: [Int]
        switch fixture {
        case .short:
            wordCounts = [6, 14, 4]
        case .nearlyFull:
            wordCounts = [8, 12, 5, 20, 7, 9, 4]
        case .long:
            wordCounts = (0..<80).map { _ in Int.random(in: 4...18, using: &generator) }
        case .media:
            wordCounts = (0..<120).map { index in
                switch index % 5 {
                case 1: 0
                case 3: Int.random(in: 80...300, using: &generator)
                default: Int.random(in: 1...12, using: &generator)
                }
            }
        case .uneven:
            wordCounts = (0..<70).map { index in
                switch index % 9 {
                case 2: Int.random(in: 120...260, using: &generator)
                case 6: Int.random(in: 40...90, using: &generator)
                default: Int.random(in: 1...10, using: &generator)
                }
            }
        }
        return wordCounts.enumerated().map { index, words in
            message(index: index + 1, chatID: chatID, isSender: index % 3 == 1, words: words)
        }
    }

    static func message(index: Int, chatID: String, isSender: Bool, words: Int? = nil, text: String? = nil) -> Message {
        // No words is a photo.
        let isPhoto = words == 0 && text == nil
        let body = isPhoto ? nil : text ?? (0..<(words ?? 6)).map { lorem[($0 * 7 + index) % lorem.count] }.joined(separator: " ")
        let sender = isSender ? "@me:lab" : "@them:lab"
        return Message(
            id: "\(chatID)-\(index)", chatID: chatID, senderID: sender,
            senderName: isSender ? "Me" : "Them", sender: nil,
            timestamp: Date(timeIntervalSince1970: 1_790_000_000 + Double(index) * 60),
            sortKey: String(index), text: body, formattedText: nil, isSender: isSender,
            attachments: isPhoto ? [photo(index: index)] : nil, isUnread: false, reactions: nil, linkedMessageID: nil,
            isDeleted: nil, transactionID: nil, threadRootID: nil, isThreadBroadcast: nil,
            thread: nil, isForwarded: nil, isNotice: nil, deliveryStatus: nil,
            deliveryError: nil, linkPreview: nil, linkPreviewURL: nil
        )
    }

    /// A photo of one of a few shapes, read from a file the lab writes.
    private static func photo(index: Int) -> Attachment {
        let shapes = [(1200, 1600), (1600, 900), (1000, 1000), (900, 2000)]
        let (width, height) = shapes[index % shapes.count]
        let url = photoURL(width: width, height: height)
        let json = """
        {"id": "\(url.absoluteString)#\(index)", "type": "img", "srcURL": "\(url.absoluteString)", "mimeType": "image/jpeg", "fileName": "photo\(index).jpg", "size": {"width": \(width), "height": \(height)}}
        """
        return try! JSONDecoder().decode(Attachment.self, from: Data(json.utf8))
    }

    private static func photoURL(width: Int, height: Int) -> URL {
        let url = URL.cachesDirectory.appending(path: "lab-photo-\(width)x\(height).jpg")
        #if os(iOS)
        if !FileManager.default.fileExists(atPath: url.path()) {
            let size = CGSize(width: width / 4, height: height / 4)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(hue: CGFloat(width % 7) / 7, saturation: 0.5, brightness: 0.8, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            try? image.jpegData(compressionQuality: 0.7)?.write(to: url)
        }
        #endif
        return url
    }

    private static let lorem = """
    lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et \
    dolore magna aliqua enim ad minim veniam quis nostrud exercitation ullamco laboris nisi aliquip ex ea \
    commodo consequat duis aute irure in reprehenderit voluptate velit esse cillum fugiat nulla pariatur
    """.split(separator: " ").map(String.init)
}

/// A deterministic random number generator, so each fixture is the same every run.
struct TimelineLabRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
#endif
