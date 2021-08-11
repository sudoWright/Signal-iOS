//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import YYImage
import AVKit
import PromiseKit

/// Model object for a looping video asset
/// Any LoopingVideoViews playing this instance will all be kept in sync
@objc
public class LoopingVideo: NSObject {
    fileprivate let assetPromise: Guarantee<AVAsset?>
    fileprivate var asset: AVAsset? { assetPromise.value.flatMap { $0 } }

    @objc
    public init?(url: URL) {
        guard OWSMediaUtils.isVideoOfValidContentTypeAndSize(path: url.path) else {
            return nil
        }
        assetPromise = firstly(on: .global(qos: .userInitiated)) { AVAsset(url: url) }
        super.init()
    }

    func createPlayerItem() -> AVPlayerItem? {
        guard let asset = asset else { return nil }
        let item = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["tracks"])
        return OWSMediaUtils.isValidVideo(asset: asset) ? item : nil
    }

    deinit {
        asset?.cancelLoading()
    }
}

private class LoopingVideoPlayer: AVPlayer {

    override init() {
        super.init()
        sharedInit()
    }

    override init(url: URL) {
        super.init(url: url)
        sharedInit()

    }

    override init(playerItem item: AVPlayerItem?) {
        super.init(playerItem: item)
        sharedInit()
    }

    private func sharedInit() {
        if let item = currentItem {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.playerItemDidPlayToCompletion(_:)),
                name: .AVPlayerItemDidPlayToEndTime,
                object: item)
        }

        isMuted = true
        allowsExternalPlayback = true
        if #available(iOS 12, *) {
            preventsDisplaySleepDuringVideoPlayback = false
        }
    }

    override func replaceCurrentItem(with newItem: AVPlayerItem?) {
        readyStatusObserver = nil

        if let oldItem = currentItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: oldItem)
            oldItem.cancelPendingSeeks()
        }

        super.replaceCurrentItem(with: newItem)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.playerItemDidPlayToCompletion(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: newItem)
    }

    @objc private func playerItemDidPlayToCompletion(_ notification: NSNotification) {
        guard (notification.object as AnyObject) === currentItem else { return }
        seek(to: .zero)
        play()
    }

    private var readyStatusObserver: NSKeyValueObservation?
    override public func play() {
        // Don't bother if we're already playing, or we don't have an item
        guard let item = currentItem, rate == 0 else { return }

        if item.status == .readyToPlay {
            readyStatusObserver = nil
            super.play()
        } else if readyStatusObserver == nil {
            // We're not ready to play, set up an observer to play when ready
            readyStatusObserver = item.observe(\.status) { [weak self] _, _  in
                guard let self = self, item === self.currentItem else { return }
                if item.status == .readyToPlay {
                    self.play()
                }
            }
        }
    }
}

// MARK: -

@objc
public protocol LoopingVideoViewDelegate: AnyObject {
    func loopingVideoViewChangedPlayerItem()
}

// MARK: -

@objc
public class LoopingVideoView: UIView {
    @objc
    public weak var delegate: LoopingVideoViewDelegate?
    
    private let player = LoopingVideoPlayer()

    @objc
    public var video: LoopingVideo? {
        didSet {
            guard video !== oldValue else { return }
            player.replaceCurrentItem(with: nil)
            invalidateIntrinsicContentSize()

            if let assetPromise = video?.assetPromise {
                firstly {
                    assetPromise
                }.map(on: .global(qos: .userInitiated)) { [weak self] asset -> Bool in
                    guard let self = self,
                          let asset = asset,
                          asset === self.video?.asset else {
                        return false
                    }
                    let playerItem = AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["tracks"])
                    self.player.replaceCurrentItem(with: playerItem)
                    self.player.play()
                    return true
                }.done(on: .main) { [weak self] didLoadPlayer in
                    guard let self = self,
                          didLoadPlayer else {
                        return
                    }
                    self.invalidateIntrinsicContentSize()
                    self.delegate?.loopingVideoViewChangedPlayerItem()
                }
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.player = player
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer {
        layer as? AVPlayerLayer ?? {
            owsFailDebug("Unexpected player type")
            return AVPlayerLayer()
        }()
    }

    override public var contentMode: UIView.ContentMode {
        didSet {
            switch contentMode {
            case .scaleAspectFill: playerLayer.videoGravity = .resizeAspectFill
            case .scaleToFill: playerLayer.videoGravity = .resize
            case .scaleAspectFit: playerLayer.videoGravity = .resizeAspect
            default: playerLayer.videoGravity = .resizeAspect
            }
        }
    }

    override public var intrinsicContentSize: CGSize {
        guard let asset = video?.asset else {
            // If we have an outstanding promise, invalidate the size once it's complete
            // If there isn't, -noIntrinsicMetric is valid
            if video?.assetPromise.isPending == true {
                video?.assetPromise.done { _ in self.invalidateIntrinsicContentSize() }
            }
            return CGSize(square: UIView.noIntrinsicMetric)
        }

        // Tracks will always be loaded by LoopingVideo
        return asset.tracks(withMediaType: .video)
            .map { $0.naturalSize }
            .reduce(.zero) {
                CGSize(width: max($0.width, $1.width),
                       height: max($0.height, $1.height))
            }
    }
}
