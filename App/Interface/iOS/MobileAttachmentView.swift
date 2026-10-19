#if os(iOS)
import UIKit
import AVKit

@MainActor
final class MobileAttachmentView: UIView {
    private let attachment: Attachment
    private let context: AppContext
    private let title: String
    private let outgoing: Bool
    private let observation = ObservationLifetime()
    private var task: Task<Void, Never>?
    private let play = UIButton(type: .system)
    private var slider: UISlider?
    private var time: UILabel?
    private var video: AVPlayerViewController?
    var onPreview: (() -> Void)?

    init(attachment: Attachment, context: AppContext, title: String, outgoing: Bool) {
        self.outgoing = outgoing
        self.attachment = attachment; self.context = context; self.title = title
        super.init(frame: .zero)
        let stack = UIStackView(vertical: [], spacing: 6); addSubview(stack); stack.pinEdges(to: self)
        if attachment.isImage {
            let image = UIImageView(); image.contentMode = .scaleAspectFit; image.backgroundColor = .secondarySystemBackground
            image.layer.cornerRadius = 12; image.clipsToBounds = true; image.isUserInteractionEnabled = true
            image.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(preview)))
            stack.addArrangedSubview(image)
            let width = CGFloat(attachment.size?.width ?? 300), height = CGFloat(attachment.size?.height ?? 200)
            let maximumWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 275 : 400
            let scale = min(1, maximumWidth / max(1, width), 500 / max(1, height))
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: width * scale), image.heightAnchor.constraint(equalToConstant: height * scale)])
            task = Task { [weak image] in
                guard let source = attachment.resolvedURL else { return }
                let result = await NativeImages.image(source, animated: attachment.isGif == true || attachment.mimeType == "image/gif")
                guard !Task.isCancelled else { return }; image?.image = result
            }
        } else if attachment.isVideo {
            let controller = AVPlayerViewController(); video = controller
            stack.addArrangedSubview(controller.view)
            let width = CGFloat(attachment.size?.width ?? 400), height = CGFloat(attachment.size?.height ?? 400)
            let maximumWidth: CGFloat = UIDevice.current.userInterfaceIdiom == .phone ? 275 : 400
            let scale = min(1, maximumWidth / max(1, width), 500 / max(1, height))
            NSLayoutConstraint.activate([controller.view.widthAnchor.constraint(equalToConstant: width * scale), controller.view.heightAnchor.constraint(equalToConstant: height * scale)])
            task = Task { [weak self] in
                do {
                    let url = try await AttachmentFiles.load(attachment)
                    guard !Task.isCancelled else { return }
                    let player = AVPlayer(url: url); controller.player = player; player.isMuted = UserDefaults.standard.bool(forKey: "muteOnPlay")
                    if UserDefaults.standard.object(forKey: "autoplay") == nil || UserDefaults.standard.bool(forKey: "autoplay") { player.play() }
                } catch { self?.context.chats.messagesError = error.localizedDescription }
            }
        } else if attachment.isAudio {
            play.setImage(UIImage(systemName: "play.fill"), for: .normal)
            play.addAction(UIAction { [weak self] _ in self?.playAudio() }, for: .touchUpInside)
            let slider = UISlider(); self.slider = slider
            slider.addTarget(self, action: #selector(seek(_:)), for: .valueChanged)
            let label = UILabel(); label.font = .preferredFont(forTextStyle: .caption1); time = label
            let row = UIStackView(arrangedSubviews: [play, slider, label]); row.spacing = 8; row.alignment = .center
            play.setPreferredSymbolConfiguration(.init(textStyle: .title2), forImageIn: .normal)
            slider.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let bubble = MobileBubbleView(outgoing: outgoing); bubble.addSubview(row); row.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12), row.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8), row.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8)])
            stack.addArrangedSubview(bubble)
            observation.track { [weak self] in self?.renderAudio() }
        } else {
            let file = MobileFileAttachmentView(attachment: attachment, outgoing: outgoing) { [weak self] in self?.onPreview?() }
            stack.addArrangedSubview(file)
        }
    }
    required init?(coder: NSCoder) { nil }
    @objc private func preview() { onPreview?() }
    private func renderAudio() {
        let audio = context.audio; let current = audio.currentAttachmentURL == attachment.resolvedURL
        let playing = current && audio.isAudioPlaying
        play.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        slider?.maximumValue = Float(max(1, current ? audio.duration : (attachment.duration ?? 0)))
        if slider?.isTracking != true { slider?.value = Float(current ? audio.currentTime : 0) }
        slider?.isEnabled = current
        time?.text = Duration.seconds(current ? audio.currentTime : (attachment.duration ?? 0)).formatted(.time(pattern: .minuteSecond))
    }
    private func playAudio() {
        if context.audio.currentAttachmentURL == attachment.resolvedURL { context.audio.toggleAudioPlayback(); return }
        play.isEnabled = false
        task = Task { [weak self] in
            guard let self else { return }; defer { play.isEnabled = true }
            do {
                let url = try await AttachmentFiles.playableAudio(attachment)
                guard !Task.isCancelled, let source = attachment.resolvedURL else { return }
                await context.audio.play(attachmentURL: source, playableURL: url, givenDuration: attachment.duration, title: title)
            } catch { context.chats.messagesError = error.localizedDescription }
        }
    }
    @objc private func seek(_ sender: UISlider) { context.audio.seek(to: Double(sender.value)) }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { video?.player?.pause(); return }
        guard let video, video.parent == nil else { return }
        var responder: UIResponder? = next
        while let current = responder {
            if let parent = current as? UIViewController { parent.addChild(video); video.didMove(toParent: parent); break }
            responder = current.next
        }
    }
    isolated deinit { task?.cancel(); video?.player?.pause(); video?.willMove(toParent: nil); video?.removeFromParent() }
}
#endif
