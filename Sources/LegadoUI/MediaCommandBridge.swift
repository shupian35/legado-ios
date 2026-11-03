#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import Foundation
import LegadoCore

#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// The lock-screen / headset buttons of the read aloud.
///
/// Upstream `receiver/MediaButtonReceiver.kt` and
/// `service/BaseReadAloudService.kt:594-670` register the six media actions
/// (上一章 / 上一段 / 暂停·继续 / 下一段 / 下一章 / 停止) with the Android media
/// session. iOS offers the same surface through `MPRemoteCommandCenter`, so
/// the port registers the same six actions there.
///
/// The Linux build uses the no-op stand-in below, so the reader code compiles
/// on every platform.
public final class MediaCommandBridge {

    /// Moves to the previous chapter.
    public var onPreviousChapter: (() -> Void)?
    /// Moves to the previous paragraph of the read aloud.
    public var onPreviousParagraph: (() -> Void)?
    /// Pauses or continues the read aloud.
    public var onTogglePlayPause: (() -> Void)?
    /// Moves to the next paragraph of the read aloud.
    public var onNextParagraph: (() -> Void)?
    /// Moves to the next chapter.
    public var onNextChapter: (() -> Void)?
    /// Stops the read aloud.
    public var onStop: (() -> Void)?

    #if canImport(MediaPlayer)
    private let center = MPRemoteCommandCenter.shared()
    /// The tokens of the registered handlers — `MPRemoteCommandCenter` is a
    /// process wide singleton, so the handlers have to be removed again when
    /// the bridge goes away.
    private var targets: [(command: MPRemoteCommand, token: Any)] = []
    #endif

    public init() {
        #if canImport(MediaPlayer)
        // The skip / previous / next commands are disabled by default — the
        // lock screen only shows them when they are enabled explicitly.
        center.previousTrackCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true

        targets.append((center.previousTrackCommand, center.previousTrackCommand.addTarget { [weak self] _ in
            self?.onPreviousChapter?()
            return .success
        }))
        targets.append((center.nextTrackCommand, center.nextTrackCommand.addTarget { [weak self] _ in
            self?.onNextChapter?()
            return .success
        }))
        targets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }))
        targets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in
            self?.onTogglePlayPause?()
            return .success
        }))
        targets.append((center.stopCommand, center.stopCommand.addTarget { [weak self] _ in
            self?.onStop?()
            return .success
        }))
        // The upstream skips the paragraph with the media buttons when the
        // preference `mediaButtonPerNext` is off — it jumps a chapter.
        targets.append((center.skipForwardCommand, center.skipForwardCommand.addTarget { [weak self] _ in
            self?.onNextParagraph?()
            return .success
        }))
        targets.append((center.skipBackwardCommand, center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.onPreviousParagraph?()
            return .success
        }))
        #endif
    }

    deinit {
        #if canImport(MediaPlayer)
        for target in targets {
            target.command.removeTarget(target.token)
        }
        center.previousTrackCommand.isEnabled = false
        center.nextTrackCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
        targets.removeAll()
        #endif
    }

    /// Publishes the now-playing information (the lock screen).
    public func updateNowPlaying(bookName: String, chapterTitle: String, isPlaying: Bool) {
        #if canImport(MediaPlayer)
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = chapterTitle
        info[MPMediaItemPropertyAlbumTitle] = bookName
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    /// Removes the now-playing information (the lock screen).
    public func clearNowPlaying() {
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }
}
