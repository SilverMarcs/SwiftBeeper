#if DEBUG && os(iOS)
import QuartzCore
import UIKit

/// Opens the lab's chats one after another (`RELAY_TIMELINE_LAB_CYCLES=n`)
/// and logs where the timeline rests against where it can scroll, and how
/// much of its visible content has drawn rows: after opening, with the
/// software keyboard up and down, and as messages are sent and received.
/// `RELAY_TIMELINE_LAB_STALL=<ms>` blocks the main thread at random around
/// opens. Writes Documents/timeline-lab.log, then exits.
@MainActor
enum TimelineLabProbe {
    private static let handle: FileHandle? = {
        let url = URL.documentsDirectory.appending(path: "timeline-lab.log")
        FileManager.default.createFile(atPath: url.path(), contents: nil)
        return try? FileHandle(forWritingTo: url)
    }()

    static func log(_ line: String) {
        handle?.write(Data(String(format: "%.3f %@\n", CACurrentMediaTime(), line).utf8))
    }

    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static func run() async {
        guard let cycles = Int(environment["RELAY_TIMELINE_LAB_CYCLES"] ?? "") else { return }
        useSoftwareKeyboard()
        var generator = TimelineLabRandom(seed: UInt64(environment["RELAY_TIMELINE_LAB_SEED"] ?? "") ?? 7)
        let controller = TimelineLabController.shared
        let fixtures = environment["RELAY_TIMELINE_LAB_FIXTURES"]?.split(separator: ",").compactMap { TimelineLabFixture(rawValue: String($0)) }
            ?? TimelineLabFixture.allCases
        try? await Task.sleep(for: .seconds(1.5))
        // RELAY_TIMELINE_LAB_HOLD=<s>: each chat holds still this long after
        // opening and again with the keyboard up, announced by a HOLD line,
        // so a screenshot can be taken from outside the app.
        if let hold = Double(environment["RELAY_TIMELINE_LAB_HOLD"] ?? "") {
            for fixture in fixtures {
                controller.open(fixture)
                try? await Task.sleep(for: .seconds(1.5))
                log("HOLD \(fixture.rawValue)-open")
                try? await Task.sleep(for: .seconds(hold))
                composerField()?.focus()
                try? await Task.sleep(for: .seconds(1.5))
                log("HOLD \(fixture.rawValue)-keyboard")
                try? await Task.sleep(for: .seconds(hold))
                composerField()?.resignFirstResponder()
                controller.pop()
                try? await Task.sleep(for: .seconds(1.2))
            }
            log("DONE")
            exit(0)
        }
        for cycle in 0..<cycles {
            let fixture = fixtures[cycle % fixtures.count]
            // Every other open, the messages arrive after the chat opens.
            let loadsLate = (cycle / fixtures.count) % 2 == 1
            let delay = loadsLate ? Duration.milliseconds(Int.random(in: 150...600, using: &generator)) : nil
            let label = "\(cycle) \(fixture.rawValue)\(loadsLate ? "-late" : "")"
            log("OPEN \(label)")
            GeometryTracker.shared.start(label: label, until: CACurrentMediaTime() + 2.2)
            let source = controller.open(fixture, loadDelay: delay)
            injectStalls(using: &generator)
            let opened = CACurrentMediaTime()
            for moment in [0.1, 0.3, 0.7, 1.2, 2.0] {
                await wait(until: opened + moment)
                probe("\(label) open\(moment)")
            }
            if environment["RELAY_TIMELINE_LAB_KB"] != nil {
                await exerciseKeyboard(source: source, label: label, using: &generator)
            }
            if fixture == .short || fixture == .nearlyFull {
                // A message picked from search, centred and then at the top.
                for alignsTop in [false, true] {
                    if let first = source.messages.first {
                        source.messageRevealRequest = MessageRevealRequest(messageID: first.id, alignsTop: alignsTop)
                    }
                    try? await Task.sleep(for: .seconds(1.0))
                    probe("\(label) reveal\(alignsTop ? "top" : "centre")")
                }
                await grow(source: source, label: label, using: &generator)
            }
            controller.pop()
            injectStalls(using: &generator)
            try? await Task.sleep(for: .seconds(1.1))
        }
        log("DONE")
        exit(0)
    }

    /// Keyboard up, a message each way, keyboard down, a message each way.
    private static func exerciseKeyboard(source: TimelineLabSource, label: String, using generator: inout TimelineLabRandom) async {
        guard let composer = composerField() else {
            log("PROBE \(label) no-composer")
            return
        }
        GeometryTracker.shared.start(label: label, until: CACurrentMediaTime() + 9)
        log("KB show \(label)")
        composer.focus()
        try? await Task.sleep(for: .seconds(1.2))
        probe("\(label) kbshown")
        source.receive(words: Int.random(in: 3...40, using: &generator))
        try? await Task.sleep(for: .seconds(1.0))
        probe("\(label) kbrecv")
        source.send("Lab send \(label)")
        try? await Task.sleep(for: .seconds(1.4))
        probe("\(label) kbsent")
        log("KB hide \(label)")
        composer.resignFirstResponder()
        try? await Task.sleep(for: .seconds(1.2))
        probe("\(label) kbhidden")
        source.receive(words: Int.random(in: 3...40, using: &generator))
        try? await Task.sleep(for: .seconds(1.0))
        probe("\(label) recv")
        source.send("Lab send again \(label)")
        try? await Task.sleep(for: .seconds(1.4))
        probe("\(label) sent")
    }

    /// A short chat receiving messages until it's taller than the view, then
    /// the keyboard coming up over it.
    private static func grow(source: TimelineLabSource, label: String, using generator: inout TimelineLabRandom) async {
        GeometryTracker.shared.start(label: label, until: CACurrentMediaTime() + 8)
        // Rows short enough that a timeline at its end counts as near the
        // bottom once each lands, so it follows them all.
        for step in 0..<8 {
            if step % 3 == 2 {
                source.send("Lab growing \(step)")
                try? await Task.sleep(for: .seconds(1.2))
            } else {
                source.receive(words: Int.random(in: 3...10, using: &generator))
                try? await Task.sleep(for: .seconds(0.6))
            }
            probe("\(label) grow\(step)")
        }
        try? await Task.sleep(for: .seconds(0.8))
        probe("\(label) grown")
        guard environment["RELAY_TIMELINE_LAB_KB"] != nil, let composer = composerField() else { return }
        composer.focus()
        try? await Task.sleep(for: .seconds(1.2))
        probe("\(label) grownkb")
        composer.resignFirstResponder()
        try? await Task.sleep(for: .seconds(1.2))
        probe("\(label) grownkbhidden")
    }

    private static func wait(until time: CFTimeInterval) async {
        let remaining = time - CACurrentMediaTime()
        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
    }

    /// The simulator types with the Mac's keyboard; a phone shows its own.
    private static func useSoftwareKeyboard() {
        let selector = NSSelectorFromString("setHardwareLayout:")
        for mode in UITextInputMode.activeInputModes where mode.responds(to: selector) {
            mode.perform(selector, with: nil)
        }
    }

    /// Blocks the main thread a few times in the next 700 ms, as a busy
    /// phone does while a screen pushes or pops.
    private static func injectStalls(using generator: inout TimelineLabRandom) {
        guard let maximum = Int(environment["RELAY_TIMELINE_LAB_STALL"] ?? "") else { return }
        for _ in 0..<3 {
            let at = Double.random(in: 0...0.7, using: &generator)
            let length = Int.random(in: 20...maximum, using: &generator)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(at))
                log("STALL \(length)ms")
                usleep(useconds_t(length * 1000))
            }
        }
    }

    // MARK: - Measuring

    /// Logs the timeline's offset against the range it can rest in, how far
    /// it is from its end, and how much of the visible content has rows drawn.
    static func probe(_ label: String) {
        guard let scrollView = currentTimeline() else {
            log("PROBE \(label) no-timeline")
            return
        }
        let range = restingRange(of: scrollView)
        let offset = scrollView.contentOffset.y
        let insets = scrollView.adjustedContentInset
        let visible = scrollView.bounds.inset(by: UIEdgeInsets(top: insets.top, left: 0, bottom: insets.bottom, right: 0))
        // The part of the visible rect the content reaches, which rows should fill.
        let span = visible.intersection(CGRect(x: visible.minX, y: 0, width: visible.width, height: scrollView.contentSize.height))
        var intervals: [ClosedRange<CGFloat>] = []
        var hiddenLayers = 0
        collect(scrollView.layer, root: scrollView.layer, span: span, intervals: &intervals, hidden: &hiddenLayers)
        let drawn = span.isNull || span.height < 1 ? 1 : covered(intervals) / span.height
        let line = String(
            format: "PROBE %@ offset %.1f min %.1f max %.1f fromEnd %.1f over %.1f under %.1f content %.1f bounds %.1f insets %.1f/%.1f drawn %.2f hidden %d",
            label, offset, range.lowerBound, range.upperBound, range.upperBound - offset,
            offset - range.upperBound, range.lowerBound - offset, scrollView.contentSize.height,
            scrollView.bounds.height, insets.top, insets.bottom, drawn, hiddenLayers
        )
        log(line)
        if label.hasSuffix("kbshown") || label.hasSuffix("open2.0") || label.hasSuffix("grownkb"), let window = scrollView.window {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
            let name = "shot-" + label.replacing(" ", with: "_") + ".jpg"
            try? image.jpegData(compressionQuality: 0.6)?.write(to: URL.documentsDirectory.appending(path: name))
        }
    }

    /// From the top, past the bars, to the end above the composer.
    static func restingRange(of scrollView: UIScrollView) -> ClosedRange<CGFloat> {
        let insets = scrollView.adjustedContentInset
        let minimum = -insets.top
        return minimum...max(minimum, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
    }

    /// Vertical extents of drawn layers within the span. Lazy rows SwiftUI
    /// leaves undrawn keep their layers, hidden.
    private static func collect(_ layer: CALayer, root: CALayer, span: CGRect, intervals: inout [ClosedRange<CGFloat>], hidden: inout Int) {
        let frame = layer.convert(layer.bounds, to: root)
        if layer.isHidden || layer.opacity < 0.01 {
            if frame.intersects(span) { hidden += 1 }
            return
        }
        if layer !== root, layer.contents != nil || layer is CAShapeLayer || (layer.backgroundColor?.alpha ?? 0) > 0.01 {
            let clipped = frame.intersection(span)
            // Leaves out backgrounds as wide and tall as the view.
            if !clipped.isNull, clipped.height > 0, !(frame.width >= span.width * 0.95 && frame.height >= span.height * 0.9) {
                intervals.append(clipped.minY...clipped.maxY)
            }
        }
        layer.sublayers?.forEach { collect($0, root: root, span: span, intervals: &intervals, hidden: &hidden) }
    }

    private static func covered(_ intervals: [ClosedRange<CGFloat>]) -> CGFloat {
        var total: CGFloat = 0
        var current: ClosedRange<CGFloat>?
        for interval in intervals.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let open = current, interval.lowerBound <= open.upperBound + 24 {
                // Gaps between rows shorter than this count as drawn.
                current = open.lowerBound...max(open.upperBound, interval.upperBound)
            } else {
                if let open = current { total += open.upperBound - open.lowerBound }
                current = interval
            }
        }
        if let open = current { total += open.upperBound - open.lowerBound }
        return total
    }

    static func currentTimeline() -> UIScrollView? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        var found: [UIScrollView] = []
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView, !(view is UICollectionView), !(view is UITextView),
               String(describing: type(of: view)).contains("Hosting"), !view.isHidden,
               view.convert(view.bounds, to: window).intersects(window.bounds), view.bounds.height > 300 {
                found.append(scroll)
            }
            view.subviews.forEach(walk)
        }
        walk(window)
        return found.max { $0.bounds.height < $1.bounds.height }
    }

    private static func composerField() -> ComposerEditor? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        func find(_ view: UIView) -> ComposerEditor? {
            if let text = view as? ComposerEditor, text.window != nil { return text }
            for subview in view.subviews { if let found = find(subview) { return found } }
            return nil
        }
        for window in windows { if let found = find(window) { return found } }
        return nil
    }
}

/// Logs the timeline's geometry on every frame it changes, flagging frames
/// at rest outside the range it can scroll to.
@MainActor
private final class GeometryTracker: NSObject {
    static let shared = GeometryTracker()
    private var link: CADisplayLink?
    private var until: CFTimeInterval = 0
    private var label = ""
    private var last = ""

    func start(label: String, until: CFTimeInterval) {
        self.label = label
        self.until = until
        last = ""
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        guard CACurrentMediaTime() < until else {
            link?.invalidate()
            link = nil
            return
        }
        guard let scrollView = TimelineLabProbe.currentTimeline() else { return }
        let range = TimelineLabProbe.restingRange(of: scrollView)
        let offset = scrollView.contentOffset.y
        let drawnOffset = scrollView.layer.presentation()?.bounds.origin.y ?? offset
        let x = scrollView.convert(scrollView.bounds, to: nil).minX
        let outside = scrollView.contentSize.height > 1 && !scrollView.isTracking && !scrollView.isDecelerating
            && (offset < range.lowerBound - 4 || offset > range.upperBound + 4)
        let line = String(
            format: "off %.1f drawn %.1f min %.1f max %.1f fromEnd %.1f size %.1f inset %.1f/%.1f x %.0f",
            offset, drawnOffset, range.lowerBound, range.upperBound, range.upperBound - offset,
            scrollView.contentSize.height, scrollView.adjustedContentInset.top, scrollView.adjustedContentInset.bottom, x
        )
        if line != last {
            TimelineLabProbe.log("GEO \(label) " + line + (outside ? " OOR" : ""))
            last = line
        }
    }
}
#endif
