//
//  UIKit.swift
//  apple-stubs
//
//  A **type-check only** stand-in for UIKit.
//
//  The port guards its Apple-only code with `#if canImport(UIKit)`, so the
//  Linux build never type-checks it — a wrong argument label or a missing
//  method silently breaks the iOS build. This module declares the API surface
//  the port uses, so the stub build can compile those branches.
//
//  It is NOT an implementation: nothing here runs, nothing here renders.
//
//  Only the declarations the port actually uses are here; every signature
//  mirrors the real Apple API (checked against developer.apple.com).
//

import Foundation

// MARK: - The geometry

/// `CoreGraphics.CGAffineTransform` — the stub provides it because
/// swift-corelibs-foundation does not.
public struct CGAffineTransform: Equatable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var tx: CGFloat
    public var ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public init(scaleX: CGFloat, y: CGFloat) {
        self.init(a: scaleX, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    public init(translationX: CGFloat, y: CGFloat) {
        self.init(a: 1, b: 0, c: 0, d: 1, tx: translationX, ty: y)
    }
}

/// `CoreGraphics.CGColor`.
public class CGColor {
    public init() {}
}

/// `CoreGraphics.CGImage`.
public class CGImage {
    public init() {}
}

/// `CoreGraphics.CGContext` — the drawing context of the image renderer.
public class CGContext {
    public func translateBy(x: CGFloat, y: CGFloat) {}
    public func scaleBy(x: CGFloat, y: CGFloat) {}
    public func saveGState() {}
    public func restoreGState() {}
}

// MARK: - CALayer

/// `QuartzCore.CALayer`.
open class CALayer: NSObject {
    public override init() { super.init() }
}

// MARK: - UIView

/// `UIKit.UIView`.
open class UIView: NSObject {

    private let backingLayer: CALayer

    /// The layer class of the view — `UIView.layerClass`.
    open class var layerClass: AnyClass { CALayer.self }

    public override init() {
        backingLayer = CALayer()
        super.init()
    }

    /// The layer of the view.
    open var layer: CALayer { backingLayer }

    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var backgroundColor: UIColor?
    open var isHidden: Bool = false
    open var alpha: CGFloat = 1
    open var translatesAutoresizingMaskIntoConstraints: Bool = true
    open var clipsToBounds: Bool = false

    open func addSubview(_ view: UIView) {}
    open func removeFromSuperview() {}
    open func setNeedsLayout() {}
    open func layoutIfNeeded() {}

    // MARK: The layout anchors

    open var leadingAnchor: NSLayoutAnchor { NSLayoutAnchor() }
    open var trailingAnchor: NSLayoutAnchor { NSLayoutAnchor() }
    open var topAnchor: NSLayoutAnchor { NSLayoutAnchor() }
    open var bottomAnchor: NSLayoutAnchor { NSLayoutAnchor() }
    open var centerXAnchor: NSLayoutAnchor { NSLayoutAnchor() }
    open var centerYAnchor: NSLayoutAnchor { NSLayoutAnchor() }
    open var widthAnchor: NSLayoutAnchor { NSLayoutAnchor() }
    open var heightAnchor: NSLayoutAnchor { NSLayoutAnchor() }
}

/// `UIKit.NSLayoutAnchor`.
open class NSLayoutAnchor: NSObject {
    open func constraint(equalTo anchor: NSLayoutAnchor) -> NSLayoutConstraint { NSLayoutConstraint() }
    open func constraint(equalToConstant constant: CGFloat) -> NSLayoutConstraint { NSLayoutConstraint() }
}

/// `UIKit.NSLayoutConstraint`.
open class NSLayoutConstraint: NSObject {
    open var isActive: Bool = false
    open class func activate(_ constraints: [NSLayoutConstraint]) {}
}

// MARK: - UIColor / UIImage

/// `UIKit.UIColor`.
open class UIColor: NSObject {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { super.init() }
    public init(white: CGFloat, alpha: CGFloat) { super.init() }
    public convenience init?(cgColor: CGColor) { self.init(white: 0, alpha: 1) }

    open func setFill() {}
    open func setStroke() {}

    open class var white: UIColor { UIColor(white: 1, alpha: 1) }
    open class var black: UIColor { UIColor(white: 0, alpha: 1) }
    open class var clear: UIColor { UIColor(white: 0, alpha: 0) }
}

/// `UIKit.UIImage`.
open class UIImage: NSObject {
    public init?(data: Data) { super.init() }
    public init(cgImage: CGImage) { super.init() }
    public init?(named: String) { super.init() }
    open func pngData() -> Data? { nil }
    open func jpegData(compressionQuality: CGFloat) -> Data? { nil }
}

// MARK: - UIFont

/// `UIKit.UIFont`.
open class UIFont: NSObject {

    /// `UIKit.UIFont.Weight`.
    public struct Weight: RawRepresentable, Hashable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }

        public static let ultralight = Weight(rawValue: -0.8)
        public static let thin = Weight(rawValue: -0.6)
        public static let light = Weight(rawValue: -0.4)
        public static let regular = Weight(rawValue: 0)
        public static let medium = Weight(rawValue: 0.23)
        public static let semibold = Weight(rawValue: 0.3)
        public static let bold = Weight(rawValue: 0.4)
        public static let heavy = Weight(rawValue: 0.56)
        public static let black = Weight(rawValue: 0.62)
    }

    public override init() { super.init() }

    /// `UIFont(name:size:)` — a failable initializer.
    public convenience init?(name: String, size: CGFloat) { self.init() }

    open class func systemFont(ofSize size: CGFloat) -> UIFont { UIFont() }
    open class func systemFont(ofSize size: CGFloat, weight: Weight) -> UIFont { UIFont() }
    open class func boldSystemFont(ofSize size: CGFloat) -> UIFont { UIFont() }
    open class func italicSystemFont(ofSize size: CGFloat) -> UIFont { UIFont() }

    open var ascender: CGFloat { 0 }
    open var descender: CGFloat { 0 }
    open var lineHeight: CGFloat { 0 }
    open var pointSize: CGFloat { 0 }
    open var familyName: String { "" }
    open var fontName: String { "" }
}

// MARK: - UIScreen

/// `UIKit.UIScreen`.
///
/// Main actor isolated on Apple platforms — the stub mirrors that so the type
/// check catches the isolation errors.
@MainActor
open class UIScreen: NSObject {
    open class var main: UIScreen { UIScreen() }
    open var brightness: CGFloat = 1
    open var bounds: CGRect = .zero
    open var scale: CGFloat = 2
}

// MARK: - UIApplication

/// `UIKit.UIDevice` — the battery level of the device.
@MainActor
open class UIDevice: NSObject {
    open class var current: UIDevice { UIDevice() }
    open var isBatteryMonitoringEnabled: Bool = false
    open var batteryLevel: Float = -1
}

/// `UIKit.UIDevice.BatteryState`.
public enum UIDeviceBatteryState: Int {
    case unknown = 0
    case unplugged = 1
    case charging = 2
    case full = 3
}

/// `UIKit.UIInterfaceOrientationMask`.
public struct UIInterfaceOrientationMask: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let portrait = UIInterfaceOrientationMask(rawValue: 1 << 1)
    public static let portraitUpsideDown = UIInterfaceOrientationMask(rawValue: 1 << 2)
    public static let landscapeLeft = UIInterfaceOrientationMask(rawValue: 1 << 4)
    public static let landscapeRight = UIInterfaceOrientationMask(rawValue: 1 << 3)
    public static let landscape: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
    public static let all: UIInterfaceOrientationMask = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
    public static let unknown = UIInterfaceOrientationMask([])
}

/// `UIKit.UIApplication`.
///
/// Main actor isolated on Apple platforms — the stub mirrors that so the type
/// check catches the isolation errors.
@MainActor
open class UIApplication: NSObject {
    open class var shared: UIApplication { UIApplication() }

    open var isIdleTimerDisabled: Bool = false
    open var requestedOrientation: UIInterfaceOrientationMask = .portrait
    open var supportedInterfaceOrientations: UIInterfaceOrientationMask = .all
    open var alternateIconName: String?

    open func setAlternateIconName(_ alternateIconName: String?, completionHandler: ((Error?) -> Void)? = nil) {}
    open func open(_ url: URL, options: [String: Any] = [:], completionHandler: ((Bool) -> Void)? = nil) {}
}

// MARK: - UIViewController

/// `UIKit.UIStatusBarAnimation`.
public struct UIStatusBarAnimation: RawRepresentable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let none = UIStatusBarAnimation(rawValue: 0)
    public static let fade = UIStatusBarAnimation(rawValue: 1)
    public static let slide = UIStatusBarAnimation(rawValue: 2)
}

/// `UIKit.UIViewController`.
open class UIViewController: NSObject {
    open var view: UIView = UIView()
    open var children: [UIViewController] = []
    open var title: String?

    /// `UIViewController.extensionContext` — the context of a share /
    /// Today extension. The real declaration lives in Foundation; the stub
    /// puts it here so that the extension sources type-check on Linux.
    open var extensionContext: NSExtensionContext? { nil }

    open func addChild(_ child: UIViewController) {}
    open func removeFromParent() {}
    open func didMove(toParent parent: UIViewController?) {}
    open func willMove(toParent parent: UIViewController?) {}

    // The life cycle of the view controller — the stub declares it so that the
    // subclasses (the share extension) type-check.
    open func viewDidLoad() {}
    open func viewWillAppear(_ animated: Bool) {}
    open func viewDidAppear(_ animated: Bool) {}
    open func viewWillDisappear(_ animated: Bool) {}
    open func viewDidDisappear(_ animated: Bool) {}

    open var prefersStatusBarHidden: Bool { false }
    open var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .none }
    open var childForStatusBarHidden: UIViewController? { nil }
    open func setNeedsStatusBarAppearanceUpdate() {}
}

/// `Foundation.NSItemProvider` — the stub of the extension attachment.
open class NSItemProvider: NSObject {
    open func loadItem(forTypeIdentifier typeIdentifier: String, options: [Any]? = nil, completionHandler: ((Any?, Error?) -> Void)? = nil) {}
}

/// `Foundation.NSExtensionItem` — the stub of an extension input item.
open class NSExtensionItem: NSObject {
    open var attachments: [NSItemProvider]?
}

/// `Foundation.NSExtensionContext` — the stub of the extension context.
open class NSExtensionContext: NSObject {
    open var inputItems: [Any] { [] }
    open var completeItems: [Any] = []
    open func completeRequest(returningItems items: [Any]?, completionHandler: ((Bool) -> Void)? = nil) {}
    open func open(_ url: URL, completionHandler: ((Bool) -> Void)? = nil) {}
}

/// `SwiftUI.UIHostingController` — the stub puts it into UIKit so that the
/// shim and the stub cannot clash.
open class UIHostingController<Content>: UIViewController {
    open var rootView: Content
    public init(rootView: Content) {
        self.rootView = rootView
        super.init()
    }
}

// MARK: - The share sheet / the pasteboard

/// `UIKit.UIActivityViewController`.
open class UIActivityViewController: UIViewController {
    public init(activityItems: [Any], applicationActivities: [Any]?) { super.init() }
}

/// `UIKit.UIPasteboard`.
open class UIPasteboard: NSObject {
    open class var general: UIPasteboard { UIPasteboard() }
    open var string: String?
    open var url: URL?
}

// MARK: - The image renderer

/// `UIKit.UIGraphicsImageRendererFormat`.
open class UIGraphicsImageRendererFormat: NSObject {
    open var scale: CGFloat = 1
    open var opaque: Bool = false
    public override init() { super.init() }
}

/// `UIKit.UIGraphicsImageRendererContext`.
open class UIGraphicsImageRendererContext: NSObject {
    open var cgContext: CGContext { CGContext() }
    open func fill(_ rect: CGRect) {}
    open func stroke(_ rect: CGRect) {}
}

/// `UIKit.UIGraphicsImageRenderer`.
open class UIGraphicsImageRenderer: NSObject {
    public init(size: CGSize, format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()) { super.init() }
    open func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        actions(UIGraphicsImageRendererContext())
        return UIImage(cgImage: CGImage())
    }
}
