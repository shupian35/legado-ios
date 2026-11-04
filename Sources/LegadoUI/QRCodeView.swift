#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(CoreImage) && canImport(UIKit)
import CoreImage
import UIKit
#elseif canImport(CoreImage) && canImport(AppKit)
import CoreImage
import AppKit
#endif

/// The QR code generator — upstream `utils/QRCodeUtils.kt`.
///
/// The upstream uses zxing with `ErrorCorrectionLevel.H` and the margin 1; on
/// iOS the system `CIQRCodeGenerator` does the same job (documented
/// deviation: no zxing port is needed).
public enum QRCodeGenerator {

    /// The error correction levels — upstream `ErrorCorrectionLevel`.
    public enum CorrectionLevel: String, CaseIterable, Sendable {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"

        /// The CoreImage input value.
        public var identifier: String {
            switch self {
            case .low: return "L"
            case .medium: return "M"
            case .quartile: return "Q"
            case .high: return "H"
            }
        }
    }

    /// Encodes a text as a PNG image.
    ///
    /// - Parameters:
    ///   - text: the text to encode (UTF-8).
    ///   - level: the error correction level; the upstream default is `H`.
    ///   - scale: the pixels per module.
    public static func png(text: String, level: CorrectionLevel = .high, scale: Int = 10) -> Data? {
        #if canImport(CoreImage) && (canImport(UIKit) || canImport(AppKit))
        // The untyped filter API — the typed one lives in the
        // `CoreImage.CIFilterBuiltins` submodule, which is not portable.
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue(level.identifier, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
        )
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage).pngData()
        #else
        // `NSImage(cgImage:size:)` takes the size in points — a zero size
        // would encode an empty bitmap.
        return NSBitmapImageRep(cgImage: cgImage)?.representation(using: .png, properties: [:])
        #endif
        #else
        return nil
        #endif
    }
    /// Encodes a text as a PNG file in the temporary directory.
    ///
    /// The upstream's `shareWithQr` writes the PNG into the cache directory
    /// and shares it as an image (`ContextExtensions.kt:280-306`); on iOS the
    /// file is shared through the share sheet.
    public static func fileURL(
        text: String,
        level: CorrectionLevel = .high,
        fileName: String = "qr.png"
    ) -> URL? {
        guard let data = png(text: text, level: level) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

/// The QR code view of a book source — upstream `ui/association/`.
public struct QRCodeView: View {

    let text: String
    let level: QRCodeGenerator.CorrectionLevel

    public init(text: String, level: QRCodeGenerator.CorrectionLevel = .high) {
        self.text = text
        self.level = level
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("二维码")
                .font(.system(size: 16))
            qrImage
            Text("扫描二维码导入书源")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private var qrImage: some View {
        #if canImport(CoreImage) && canImport(UIKit)
        if let data = QRCodeGenerator.png(text: text, level: level),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 220, height: 220)
        } else {
            Text("二维码生成失败")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        #elseif canImport(CoreImage) && canImport(AppKit)
        if let data = QRCodeGenerator.png(text: text, level: level),
           let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 220, height: 220)
        } else {
            Text("二维码生成失败")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        #else
        Text("当前平台不支持二维码")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        #endif
    }
}
