//
//  MediaPlayer.swift
//  apple-stubs
//
//  A **type-check only** stand-in for MediaPlayer.
//
//  See `UIKit.swift` in this folder for the rationale. Only the declarations
//  the port uses are here and every signature mirrors the real Apple API.
//

import Foundation

// MARK: - The remote commands

/// `MediaPlayer.MPRemoteCommandHandlerStatus`.
public enum MPRemoteCommandHandlerStatus: Int {
    case commandFailed = 0
    case noSuchContent = 1
    case success = 2
}

/// `MediaPlayer.MPRemoteCommandEvent`.
open class MPRemoteCommandEvent: NSObject {
    open var timestamp: TimeInterval { 0 }
}

/// `MediaPlayer.MPRemoteCommand`.
open class MPRemoteCommand: NSObject {
    open var isEnabled: Bool = true
    open var localizedTitle: String = ""
    @discardableResult
    open func addTarget(_ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any {
        return NSObject()
    }
    open func removeTarget(_ target: Any) {}
}

/// `MediaPlayer.MPRemoteCommandCenter`.
open class MPRemoteCommandCenter: NSObject {
    open class func shared() -> MPRemoteCommandCenter { MPRemoteCommandCenter() }

    open var previousTrackCommand: MPRemoteCommand { MPRemoteCommand() }
    open var nextTrackCommand: MPRemoteCommand { MPRemoteCommand() }
    open var playCommand: MPRemoteCommand { MPRemoteCommand() }
    open var pauseCommand: MPRemoteCommand { MPRemoteCommand() }
    open var stopCommand: MPRemoteCommand { MPRemoteCommand() }
    open var skipForwardCommand: MPRemoteCommand { MPRemoteCommand() }
    open var skipBackwardCommand: MPRemoteCommand { MPRemoteCommand() }
    open var togglePlayPauseCommand: MPRemoteCommand { MPRemoteCommand() }
    open var changePlaybackPositionCommand: MPRemoteCommand { MPRemoteCommand() }
}

// MARK: - The now playing info

/// `MediaPlayer.MPNowPlayingInfoCenter`.
open class MPNowPlayingInfoCenter: NSObject {
    open class func `default`() -> MPNowPlayingInfoCenter { MPNowPlayingInfoCenter() }
    open var nowPlayingInfo: [String: Any]?
    open func setNowPlayingInfo(_ nowPlayingInfo: [String: Any]?) { self.nowPlayingInfo = nowPlayingInfo }
    open func clearNowPlayingInfo() { nowPlayingInfo = nil }
}

public let MPMediaItemPropertyTitle: String = "title"
public let MPMediaItemPropertyAlbumTitle: String = "albumTitle"
public let MPMediaItemPropertyArtist: String = "artist"
public let MPMediaItemPropertyPlaybackDuration: String = "playbackDuration"
public let MPNowPlayingInfoPropertyIsLiveStream: String = "MPNowPlayingInfoPropertyIsLiveStream"
public let MPNowPlayingInfoPropertyPlaybackRate: String = "MPNowPlayingInfoPropertyPlaybackRate"
public let MPNowPlayingInfoPropertyElapsedPlaybackTime: String = "MPNowPlayingInfoPropertyElapsedPlaybackTime"
public let MPNowPlayingInfoPropertyMediaType: String = "MPNowPlayingInfoPropertyMediaType"
