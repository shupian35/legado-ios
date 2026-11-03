//
//  CoreImage.swift
//  apple-stubs
//
//  A **type-check only** stand-in for CoreImage.
//
//  See `UIKit.swift` in this folder for the rationale. Only the declarations
//  the port uses are here and every signature mirrors the real Apple API.
//
//  The QR code generator of the port uses the typed filter of
//  `CoreImage.CIFilterBuiltins`; the submodule cannot be named in a Swift
//  module name (a dot is not allowed), so the typed filter lives in this
//  module as well and the port uses the untyped `CIFilter(name:)` API.
//

import Foundation
import UIKit

/// `CoreImage.CIImage`.
open class CIImage: NSObject {
    open var extent: CGRect { .zero }
    open var isInfinite: Bool { false }
    open func transformed(by transform: CGAffineTransform) -> CIImage { self }
    open func cropped(to rect: CGRect) -> CIImage { self }
}

/// `CoreImage.CIFilter`.
open class CIFilter: NSObject {
    open var outputImage: CIImage? { nil }
    open var inputImage: CIImage?

    public override init() { super.init() }

    /// `CIFilter.init(name:)`.
    public convenience init?(name: String) { self.init() }

    open func setValue(_ value: Any?, forKey key: String) {}
    open func value(forKey key: String) -> Any? { nil }
}

/// `CoreImage.CIFilterBuiltins.CIFilterQRCodeGenerator`.
public struct CIFilterQRCodeGenerator {

    /// The message that is encoded.
    public var message: Data = Data()

    /// The error correction level (`L`, `M`, `Q`, `H`).
    public var correctionLevel: String = "M"

    /// The generated image.
    public var outputImage: CIImage? { nil }
}

public extension CIFilter {
    /// `CIFilter.qrCodeGenerator()`.
    static func qrCodeGenerator() -> CIFilterQRCodeGenerator { CIFilterQRCodeGenerator() }
}

/// `CoreImage.CIContext`.
open class CIContext: NSObject {
    public override init() { super.init() }
    open func createCGImage(_ image: CIImage, from rect: CGRect) -> CGImage? { CGImage() }
    open func createCGImage(_ image: CIImage) -> CGImage? { CGImage() }
}
