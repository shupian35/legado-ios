//
//  AVFoundation.swift
//  apple-stubs
//
//  A **type-check only** stand-in for AVFoundation.
//
//  See `UIKit.swift` in this folder for the rationale. Only the declarations
//  the port uses are here and every signature mirrors the real Apple API.
//
//  The port uses AVFoundation for two things: the system speech synthesizer
//  (the read aloud) and the camera (the QR scanner).
//

import Foundation
import UIKit

// MARK: - The speech synthesizer

// MARK: - The audio session

/// `AVFoundation.AVAudioSession`.
open class AVAudioSession: NSObject {

    /// `AVAudioSession.Category`.
    public struct Category: RawRepresentable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let playback = Category(rawValue: "AVAudioSessionCategoryPlayback")
        public static let ambient = Category(rawValue: "AVAudioSessionCategoryAmbient")
        public static let soloAmbient = Category(rawValue: "AVAudioSessionCategorySoloAmbient")
        public static let record = Category(rawValue: "AVAudioSessionCategoryRecord")
        public static let playAndRecord = Category(rawValue: "AVAudioSessionCategoryPlayAndRecord")
    }

    open class func sharedInstance() -> AVAudioSession { AVAudioSession() }

    open func setCategory(_ category: Category) throws {}
    open func setActive(_ active: Bool) throws {}
    open var isOtherAudioPlaying: Bool { false }
}

// MARK: - The speech

/// `AVFoundation.AVSpeechBoundary`.
public enum AVSpeechBoundary: Int {
    case immediate = 0
    case word = 1
    case sentence = 2
}

/// `AVFoundation.AVSpeechSynthesisVoice`.
open class AVSpeechSynthesisVoice: NSObject {
    open class func voice(language: String) -> AVSpeechSynthesisVoice? { AVSpeechSynthesisVoice() }
    /// The failable initializer of the real API.
    public convenience init?(language: String) { self.init() }
    open var language: String { "" }
    open var identifier: String { "" }
}

/// `AVFoundation.AVSpeechUtterance`.
open class AVSpeechUtterance: NSObject {
    open var string: String
    open var voice: AVSpeechSynthesisVoice?
    open var rate: Float = 0.5
    open var pitchMultiplier: Float = 1.0
    open var volume: Float = 1.0
    open var voiceIdentifier: String?

    public init(string: String) {
        self.string = string
        super.init()
    }
}

/// `AVFoundation.AVSpeechSynthesizerDelegate`.
public protocol AVSpeechSynthesizerDelegate: AnyObject {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
}

/// `AVFoundation.AVSpeechSynthesizer`.
open class AVSpeechSynthesizer: NSObject {
    open weak var delegate: AVSpeechSynthesizerDelegate?
    open var isSpeaking: Bool { false }
    open var isPaused: Bool { false }
    open func speak(_ utterance: AVSpeechUtterance) {}
    @discardableResult
    open func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { false }
    open func pauseSpeaking(at boundary: AVSpeechBoundary) {}
    open func continueSpeaking() {}
}

public let AVSpeechUtteranceMinimumSpeechRate: Float = 0.0
public let AVSpeechUtteranceMaximumSpeechRate: Float = 1.0
public let AVSpeechUtteranceDefaultSpeechRate: Float = 0.5

// MARK: - The audio player

/// `AVFoundation.AVAudioPlayerDelegate`.
///
/// The real protocol declares its methods as `@objc optional` — the stub
/// gives them default implementations.
public protocol AVAudioPlayerDelegate: AnyObject {}

public extension AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {}
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {}
}

/// `AVFoundation.AVAudioPlayer`.
open class AVAudioPlayer: NSObject {
    open weak var delegate: AVAudioPlayerDelegate?
    open var isPlaying: Bool { false }
    open var duration: TimeInterval { 0 }
    open var volume: Float = 1

    public init(data: Data) throws { super.init() }
    public convenience init(contentsOf url: URL) throws { try self.init(data: Data()) }

    open func prepareToPlay() -> Bool { true }
    open func play() {}
    open func stop() {}
    open func pause() {}
}

// MARK: - The streaming player

/// `AVFoundation.AVURLAsset`.
open class AVURLAsset: NSObject {
    public let url: URL
    public init(url: URL, options: [String: Any]? = nil) {
        self.url = url
        super.init()
    }
}

/// `AVFoundation.AVPlayerItem`.
open class AVPlayerItem: NSObject {
    public let asset: AVURLAsset
    public init(asset: AVURLAsset) {
        self.asset = asset
        super.init()
    }
}

/// `AVFoundation.AVPlayer`.
open class AVPlayer: NSObject {
    public var currentItem: AVPlayerItem?
    public init(playerItem: AVPlayerItem?) {
        self.currentItem = playerItem
        super.init()
    }
    open func play() {}
    open func pause() {}
    open var rate: Float = 0
}

public extension Notification.Name {
    /// `AVFoundation.Notification.Name.AVPlayerItemDidPlayToEndTime`.
    static let AVPlayerItemDidPlayToEndTime = Notification.Name("AVPlayerItemDidPlayToEndTime")
}

// MARK: - The camera

/// `AVFoundation.AVCaptureDevice.Position`.
public enum AVCaptureDevicePosition: Int {
    case unspecified = 0
    case back = 1
    case front = 2
}

/// `AVFoundation.AVMediaType`.
public struct AVMediaType: RawRepresentable, Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video = AVMediaType(rawValue: "vide")
}

/// `AVFoundation.AVCaptureDevice`.
open class AVCaptureDevice: NSObject {
    open class func `default`(for mediaType: AVMediaType) -> AVCaptureDevice? { AVCaptureDevice() }
    open class func `default`(for mediaType: AVMediaType, position: AVCaptureDevicePosition) -> AVCaptureDevice? { AVCaptureDevice() }
}

/// `AVFoundation.AVCaptureDeviceInput`.
open class AVCaptureDeviceInput: AVCaptureInput {
    public init(device: AVCaptureDevice) throws { super.init() }
}

/// `AVFoundation.AVMetadataObject.ObjectType`.
public struct AVMetadataObjectObjectType: RawRepresentable, Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let qr = AVMetadataObjectObjectType(rawValue: "org.iso.QRCode")
    public static let ean13 = AVMetadataObjectObjectType(rawValue: "org.gs1.EAN-13")
}

/// `AVFoundation.AVMetadataObject`.
open class AVMetadataObject: NSObject {
    open var type: AVMetadataObjectObjectType { .qr }
}

/// `AVFoundation.AVMetadataMachineReadableCodeObject`.
open class AVMetadataMachineReadableCodeObject: AVMetadataObject {
    open var stringValue: String?
}

/// `AVFoundation.AVCaptureConnection`.
open class AVCaptureConnection: NSObject {}

/// `AVFoundation.AVCaptureMetadataOutputObjectsDelegate`.
public protocol AVCaptureMetadataOutputObjectsDelegate: AnyObject {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    )
}

/// `AVFoundation.AVCaptureMetadataOutput`.
open class AVCaptureMetadataOutput: AVCaptureOutput {
    open var metadataObjectTypes: [AVMetadataObjectObjectType] = []
    open func setMetadataObjectsDelegate(_ objectsDelegate: AVCaptureMetadataOutputObjectsDelegate?, queue: DispatchQueue?) {}
}

/// `AVFoundation.AVCaptureSession`.
open class AVCaptureSession: NSObject {
    open var isRunning: Bool { false }
    open var sessionPreset: AVCaptureSession.Preset = .high
    open func canAddInput(_ input: AVCaptureInput) -> Bool { true }
    open func canAddOutput(_ output: AVCaptureOutput) -> Bool { true }
    open func addInput(_ input: AVCaptureInput) {}
    open func addOutput(_ output: AVCaptureOutput) {}
    open func removeInput(_ input: AVCaptureInput) {}
    open func removeOutput(_ output: AVCaptureOutput) {}
    open func startRunning() {}
    open func stopRunning() {}
    open func commitConfiguration() {}
    open func beginConfiguration() {}

    /// `AVFoundation.AVCaptureSession.Preset`.
    public struct Preset: RawRepresentable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let high = Preset(rawValue: "AVCaptureSessionPresetHigh")
        public static let medium = Preset(rawValue: "AVCaptureSessionPresetMedium")
        public static let low = Preset(rawValue: "AVCaptureSessionPresetLow")
    }
}

/// `AVFoundation.AVCaptureInput`.
open class AVCaptureInput: NSObject {}

/// `AVFoundation.AVCaptureOutput`.
open class AVCaptureOutput: NSObject {}

/// `AVFoundation.AVLayerVideoGravity`.
///
/// On Apple the type is an `NSString` alias with the constants imported as
/// `AVLayerVideoGravity.resizeAspectFill` — the stub models it as a small
/// value type with the same members.
public struct AVLayerVideoGravity: RawRepresentable, Equatable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let resizeAspectFill = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspectFill")
    public static let resizeAspect = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityResizeAspect")
    public static let maintainAspectFill = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityMaintainAspectFill")
    public static let maintainAspect = AVLayerVideoGravity(rawValue: "AVLayerVideoGravityMaintainAspect")
}

/// `AVFoundation.AVCaptureVideoPreviewLayer`.
open class AVCaptureVideoPreviewLayer: CALayer {
    open var session: AVCaptureSession?
    open var videoGravity: AVLayerVideoGravity = .resizeAspect
}
