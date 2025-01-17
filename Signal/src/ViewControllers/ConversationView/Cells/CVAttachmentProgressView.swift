//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
import SignalServiceKit
import SignalUI

// A view for presenting attachment upload/download/failure/pending state.
public class CVAttachmentProgressView: ManualLayoutView {

    public enum Direction {
        case upload(attachmentStream: TSAttachmentStream)
        case download(attachmentPointer: TSAttachmentPointer)

        var attachmentId: TSResourceId {
            switch self {
            case .upload(let attachmentStream):
                return attachmentStream.resourceId
            case .download(let attachmentPointer):
                return attachmentPointer.resourceId
            }
        }
    }

    private let direction: Direction
    private let diameter: CGFloat
    private let isDarkThemeEnabled: Bool

    private let stateView: StateView

    private var attachmentId: TSResourceId { direction.attachmentId }

    public required init(direction: Direction,
                         diameter: CGFloat = 44,
                         isDarkThemeEnabled: Bool,
                         mediaCache: CVMediaCache) {
        self.direction = direction
        self.diameter = diameter
        self.isDarkThemeEnabled = isDarkThemeEnabled
        self.stateView = StateView(diameter: diameter,
                                   direction: direction,
                                   isDarkThemeEnabled: isDarkThemeEnabled,
                                   mediaCache: mediaCache)

        super.init(name: "CVAttachmentProgressView")

        createViews()

        configureState()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(name: String) {
        fatalError("init(name:) has not been implemented")
    }

    private enum State: Equatable {
        case none
        case tapToDownload
        case downloadFailed
        case downloadUnknownProgress
        case uploadUnknownProgress
        case downloadProgress(progress: CGFloat)
        case uploadProgress(progress: CGFloat)

        var debugDescription: String {
            switch self {
            case .none:
                return "none"
            case .tapToDownload:
                return "tapToDownload"
            case .downloadFailed:
                return "downloadFailed"
            case .downloadUnknownProgress:
                return "downloadUnknownProgress"
            case .uploadUnknownProgress:
                return "uploadUnknownProgress"
            case .downloadProgress(let progress):
                return "downloadProgress: \(progress)"
            case .uploadProgress(let progress):
                return "uploadProgress: \(progress)"
            }
        }
    }

    private class StateView: ManualLayoutView {
        private let diameter: CGFloat
        private let direction: Direction
        private let isDarkThemeEnabled: Bool
        private lazy var imageView = CVImageView()
        private var unknownProgressView: Lottie.AnimationView?
        private var progressView: Lottie.AnimationView?
        private let mediaCache: CVMediaCache

        var state: State = .none {
            didSet {
                if oldValue != state {
                    applyState(oldState: oldValue, newState: state)
                }
            }
        }

        private var isIncoming: Bool {
            switch direction {
            case .upload:
                return false
            case .download:
                return true
            }
        }

        required init(diameter: CGFloat,
                      direction: Direction,
                      isDarkThemeEnabled: Bool,
                      mediaCache: CVMediaCache) {
            self.diameter = diameter
            self.direction = direction
            self.isDarkThemeEnabled = isDarkThemeEnabled
            self.mediaCache = mediaCache

            super.init(name: "CVAttachmentProgressView.StateView")

            applyState(oldState: .none, newState: .none)
        }

        @available(*, unavailable, message: "use other constructor instead.")
            public required init(name: String) {
                fatalError("init(name:) has not been implemented")
        }

        private func applyState(oldState: State, newState: State) {

            switch newState {
            case .none:
                reset()
            case .tapToDownload:
                if oldState != newState {
                    presentIcon(templateName: Theme.iconName(.arrowDown), isInsideProgress: false)
                }
            case .downloadFailed:
                if oldState != newState {
                    presentIcon(templateName: Theme.iconName(.refresh), isInsideProgress: false)
                }
            case .downloadProgress(let progress):
                switch oldState {
                case .downloadProgress:
                    updateProgress(progress: progress)
                default:
                    presentProgress(progress: progress)
                    presentIcon(templateName: Theme.iconName(.buttonX), isInsideProgress: true)
                }
            case .uploadProgress(let progress):
                switch oldState {
                case .uploadProgress:
                    updateProgress(progress: progress)
                default:
                    presentProgress(progress: progress)
                }
            case .downloadUnknownProgress:
                presentUnknownProgress()
                presentIcon(templateName: Theme.iconName(.buttonX), isInsideProgress: true)
            case .uploadUnknownProgress:
                presentUnknownProgress()
            }
        }

        private func presentIcon(templateName: String,
                                 isInsideProgress: Bool) {
            if !isInsideProgress {
                reset()
            }

            imageView.setTemplateImageName(templateName, tintColor: .ows_white)
            addSubviewToCenterOnSuperview(imageView, size: .square(floor(0.44 * diameter)))
        }

        private func presentProgress(progress: CGFloat) {
            reset()

            let animationName: String
            if diameter <= 44 {
                animationName = "determinate_spinner_44"
            } else {
                animationName = "determinate_spinner_56"
            }
            let animationView = ensureAnimationView(progressView, animationName: animationName)
            owsAssertDebug(animationView.animation != nil)
            progressView = animationView
            animationView.backgroundBehavior = .pause
            animationView.loopMode = .playOnce
            animationView.contentMode = .scaleAspectFit
            // We DO NOT play this animation; we "scrub" it to reflect
            // attachment upload/download progress.
            updateProgress(progress: progress)
            addSubviewToFillSuperviewEdges(animationView)
        }

        private func presentUnknownProgress() {
            reset()

            let animationName: String
            if diameter <= 44 {
                animationName = "indeterminate_spinner_44"
            } else {
                animationName = "indeterminate_spinner_56"
            }
            let animationView = ensureAnimationView(unknownProgressView, animationName: animationName)
            owsAssertDebug(animationView.animation != nil)
            unknownProgressView = animationView
            animationView.backgroundBehavior = .pauseAndRestore
            animationView.loopMode = .loop
            animationView.contentMode = .scaleAspectFit
            animationView.play()

            addSubviewToFillSuperviewEdges(animationView)
        }

        private func ensureAnimationView(_ animationView: Lottie.AnimationView?,
                                         animationName: String) -> AnimationView {
            if let animationView = animationView {
                return animationView
            } else {
                return mediaCache.buildLottieAnimationView(name: animationName)
            }
        }

        private func updateProgress(progress: CGFloat) {
            guard let progressView = progressView else {
                owsFailDebug("Missing progressView.")
                return
            }
            guard let animation = progressView.animation else {
                owsFailDebug("Missing animation.")
                return
            }

            // We DO NOT play this animation; we "scrub" it to reflect
            // attachment upload/download progress.
            progressView.currentFrame = progress.lerp(animation.startFrame,
                                                      animation.endFrame)
        }

        public override func reset() {
            super.reset()

            progressView?.stop()
            unknownProgressView?.stop()
            imageView.image = nil
        }
    }

    private func createViews() {
        let innerContentView = self.stateView

        let circleView = ManualLayoutView.circleView(name: "circleView")
        circleView.backgroundColor = .ows_blackAlpha50
        circleView.addSubviewToCenterOnSuperview(innerContentView, size: .square(diameter))
        addSubviewToFillSuperviewEdges(circleView)
    }

    public var layoutSize: CGSize {
        .square(diameter)
    }

    private func configureState() {
        switch direction {
        case .upload(let attachmentStream):
            stateView.state = .uploadUnknownProgress

            updateUploadProgress(attachmentStream: attachmentStream)

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(processUploadNotification(notification:)),
                name: Upload.Constants.uploadProgressNotification,
                object: nil
            )

        case .download(let attachmentPointer):
            switch attachmentPointer.state {
            case .failed:
                stateView.state = .downloadFailed
            case .pendingMessageRequest, .pendingManualDownload:
                stateView.state = .tapToDownload
            case .enqueued, .downloading:
                updateDownloadProgress()

                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(processDownloadNotification(notification:)),
                    name: TSResourceDownloads.attachmentDownloadProgressNotification,
                    object: nil
                )
            }
        }
    }

    @objc
    private func processDownloadNotification(notification: Notification) {
        guard
            let attachmentId = notification.userInfo?[TSResourceDownloads.attachmentDownloadAttachmentIDKey] as? TSResourceId
        else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard attachmentId == self.attachmentId else {
            return
        }
        updateDownloadProgress()
    }

    private func updateDownloadProgress() {
        AssertIsOnMainThread()

        let progress = databaseStorage.read { tx in
            return DependenciesBridge.shared.tsResourceDownloadManager
                .downloadProgress(for: attachmentId, tx: tx.asV2Read)
        }

        guard let progress else {
            Logger.warn("No progress for attachment.")
            stateView.state = .downloadUnknownProgress
            return
        }

        updateState(downloadProgress: progress)
    }

    private func updateState(downloadProgress progress: CGFloat?) {
        guard let progress = progress else {
            stateView.state = .downloadUnknownProgress
            return
        }
        if progress.isNaN {
            owsFailDebug("Progress is nan.")
            stateView.state = .downloadUnknownProgress
        } else if progress > 0 {
            stateView.state = .downloadProgress(progress: CGFloat(progress))
        } else {
            stateView.state = .downloadUnknownProgress
        }
    }

    @objc
    private func processUploadNotification(notification: Notification) {
        guard let notificationAttachmentId = notification.userInfo?[Upload.Constants.uploadAttachmentIDKey] as? String else {
            owsFailDebug("Missing notificationAttachmentId.")
            return
        }
        guard .legacy(uniqueId: notificationAttachmentId) == attachmentId else {
            return
        }
        guard let progress = notification.userInfo?[Upload.Constants.uploadProgressKey] as? NSNumber else {
            owsFailDebug("Missing progress.")
            stateView.state = .uploadUnknownProgress
            return
        }

        switch direction {
        case .upload(let attachmentStream):
            guard !attachmentStream.isUploaded else {
                stateView.state = .uploadProgress(progress: 1)
                return
            }
        case .download:
            owsFailDebug("Invalid attachment.")
            stateView.state = .uploadUnknownProgress
            return
        }

        updateState(uploadProgress: progress)
    }

    private func updateState(uploadProgress progress: NSNumber?) {
        guard let progress = progress?.floatValue else {
            stateView.state = .uploadUnknownProgress
            return
        }
        if progress.isNaN {
            owsFailDebug("Progress is nan.")
            stateView.state = .uploadUnknownProgress
        } else if progress > 0 {
            stateView.state = .uploadProgress(progress: CGFloat(progress))
        } else {
            stateView.state = .uploadUnknownProgress
        }
    }

    private func updateUploadProgress(attachmentStream: TSAttachmentStream) {
        AssertIsOnMainThread()

        if attachmentStream.isUploaded {
            stateView.state = .uploadProgress(progress: 1)
        } else {
            stateView.state = .uploadUnknownProgress
        }
    }

    public enum ProgressType {
        case none
        case uploading(attachmentStream: TSAttachmentStream)
        case pendingDownload(attachmentPointer: TSAttachmentPointer)
        case downloading(attachmentPointer: TSAttachmentPointer)
        case unknown
    }

    public static func progressType(forAttachment attachment: TSAttachment,
                                    interaction: TSInteraction) -> ProgressType {

        if let attachmentStream = attachment as? TSAttachmentStream {
            if let outgoingMessage = interaction as? TSOutgoingMessage {
                let hasSendFailed = outgoingMessage.messageState == .failed
                let wasNotCreatedLocally = outgoingMessage.wasNotCreatedLocally
                guard !attachmentStream.isUploaded,
                        !wasNotCreatedLocally,
                        !hasSendFailed else {
                    return .none
                }
                return .uploading(attachmentStream: attachmentStream)
            } else if interaction is TSIncomingMessage {
                return .none
            } else {
                owsFailDebug("Unexpected interaction: \(type(of: interaction))")
                return .unknown
            }
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            switch attachmentPointer.state {
            case .pendingMessageRequest, .pendingManualDownload:
                return .pendingDownload(attachmentPointer: attachmentPointer)
            case .failed, .enqueued, .downloading:
                return .downloading(attachmentPointer: attachmentPointer)
            }

        } else {
            owsFailDebug("Unexpected attachment: \(type(of: attachment))")
            return .unknown
        }
    }
}
