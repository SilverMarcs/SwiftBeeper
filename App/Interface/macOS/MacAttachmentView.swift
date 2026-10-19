#if os(macOS)
import AppKit
import AVKit

@MainActor
final class MacAttachmentView: NSView {
    private let attachment: Attachment
    private let context: AppContext
    private let title: String
    private let outgoing: Bool
    private let observation = ObservationLifetime()
    private var task: Task<Void, Never>?
    private var player: AVPlayer?
    private var videoView: AVPlayerView?
    private let stack = NSStackView(vertical: [])
    private let image = NSImageView()
    private var playButton: MacActionButton?
    private var slider: NSSlider?
    private var timeLabel: NSTextField?
    var onPreview: (() -> Void)?

    init(attachment: Attachment, context: AppContext, title: String, outgoing: Bool) {
        self.outgoing = outgoing
        self.attachment = attachment; self.context = context; self.title = title
        super.init(frame: .zero)
        addSubview(stack); stack.pinEdges(to: self)
        let name = attachment.fileName ?? attachment.typeLabel.capitalized
        if attachment.isImage {
            image.imageScaling = .scaleProportionallyUpOrDown; image.animates = true
            image.wantsLayer = true; image.layer?.cornerRadius = 12; image.layer?.masksToBounds = true
            image.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(preview)))
            stack.addArrangedSubview(image)
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: imageSize.width), image.heightAnchor.constraint(equalToConstant: imageSize.height)])
            let source = attachment.resolvedURL
            task = Task { [weak self] in
                guard let source else { return }
                let result = await NativeImages.image(source, animated: attachment.isGif == true || attachment.mimeType == "image/gif")
                guard !Task.isCancelled else { return }
                self?.image.image = result
            }
        } else if attachment.isVideo {
            let video = AVPlayerView(); video.controlsStyle = .inline
            videoView = video
            stack.addArrangedSubview(video)
            NSLayoutConstraint.activate([video.widthAnchor.constraint(equalToConstant: imageSize.width), video.heightAnchor.constraint(equalToConstant: imageSize.height)])
            video.showsFullScreenToggleButton = true
            task = Task { [weak self] in
                do {
                    let url = try await AttachmentFiles.load(attachment)
                    guard !Task.isCancelled, let self else { return }
                    let player = AVPlayer(url: url); self.player = player; video.player = player
                    player.isMuted = UserDefaults.standard.bool(forKey: "muteOnPlay")
                    if UserDefaults.standard.object(forKey: "autoplay") == nil || UserDefaults.standard.bool(forKey: "autoplay") { player.play() }
                } catch { self?.showError(error) }
            }
        } else if attachment.isAudio {
            let play = MacActionButton("Play Audio", symbol: "play.fill") { [weak self] in self?.playAudio() }
            playButton = play
            let slider = NSSlider(value: 0, minValue: 0, maxValue: max(1, attachment.duration ?? 0), target: self, action: #selector(seek(_:)))
            self.slider = slider
            let time = NSTextField(labelWithString: ""); time.font = .preferredFont(forTextStyle: .caption1); timeLabel = time
            let row = NSStackView(views: [play, slider, time]); row.spacing = 8
            play.isBordered = false; play.image = play.image?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let bubble = MacBubbleView(outgoing: outgoing, radius: 12); bubble.addSubview(row)
            row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12), row.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8), row.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)])
            stack.addArrangedSubview(bubble)
            observation.track { [weak self] in self?.renderAudio() }
        } else {
            let file = MacFileAttachmentView(attachment: attachment, outgoing: outgoing) { [weak self] in self?.onPreview?() }
            stack.addArrangedSubview(file)
        }
    }
    required init?(coder: NSCoder) { nil }
    private var imageSize: NSSize {
        let original = NSSize(width: CGFloat(attachment.size?.width ?? (attachment.isVideo ? 400 : 300)), height: CGFloat(attachment.size?.height ?? (attachment.isVideo ? 400 : 200)))
        let scale = min(1, 400 / max(1, original.width), 500 / max(1, original.height))
        return NSSize(width: original.width * scale, height: original.height * scale)
    }
    @objc private func preview() { onPreview?() }
    private func renderAudio() {
        let audio = context.audio
        let current = audio.currentAttachmentURL == attachment.resolvedURL
        let playing = current && audio.isAudioPlaying
        playButton?.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: nil)
        slider?.maxValue = max(1, current ? audio.duration : (attachment.duration ?? 0))
        slider?.doubleValue = current ? audio.currentTime : 0
        slider?.isEnabled = current
        timeLabel?.stringValue = Duration.seconds(current ? audio.currentTime : (attachment.duration ?? 0)).formatted(.time(pattern: .minuteSecond))
    }
    private func playAudio() {
        if context.audio.currentAttachmentURL == attachment.resolvedURL { context.audio.toggleAudioPlayback(); return }
        playButton?.isEnabled = false
        task = Task { [weak self] in
            guard let self else { return }
            defer { playButton?.isEnabled = true }
            do {
                let url = try await AttachmentFiles.playableAudio(attachment)
                guard !Task.isCancelled, let source = attachment.resolvedURL else { return }
                await context.audio.play(attachmentURL: source, playableURL: url, givenDuration: attachment.duration, title: title)
            } catch { showError(error) }
        }
    }
    @objc private func seek(_ sender: NSSlider) { context.audio.seek(to: sender.doubleValue) }
    private func showError(_ error: Error) { context.chats.messagesError = error.localizedDescription }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { player?.pause() } }
    isolated deinit { task?.cancel() }
}
#endif
