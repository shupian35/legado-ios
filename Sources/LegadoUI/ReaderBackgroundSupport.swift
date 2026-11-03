#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import Foundation
import LegadoCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Loads a background image from the disk.
///
/// The upstream `ReadBookConfig.curBgDrawable` stretches the image to exactly
/// the view size and puts a layer of the mean colour underneath it.
final class ReaderBackgroundImageLoader: ObservableObject {

    @Published var data: Data?
    @Published var size: CGSizeLike = CGSizeLike(width: 0, height: 0)

    func load(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let loaded = try? Data(contentsOf: url) else { return }
        data = loaded
        size = CGSizeLike(width: Double(loaded.count), height: Double(loaded.count))
    }
}

/// The background of the reader — upstream `ReadBookConfig.curBgDrawable`.
public struct ReaderBackgroundSupport: View {

    let preset: ReaderBackgroundPreset
    let mode: ReaderDisplayMode
    let root: URL

    @ObservedObject private var loader = ReaderBackgroundImageLoader()

    public init(preset: ReaderBackgroundPreset, mode: ReaderDisplayMode, root: URL) {
        self.preset = preset
        self.mode = mode
        self.root = root
    }

    public var body: some View {
        ZStack {
            // The upstream applies the opacity of the style to the background
            // drawable (`PageView.kt:280`: `ReadBookConfig.bg?.alpha =
            // (ReadBookConfig.bgAlpha / 100f * 255).toInt()`), the colour and
            // the image are the same drawable there.
            ColorHex.color(preset.backgroundString(for: mode), fallback: .white)
                .opacity(isColourBackground ? backgroundAlpha : 1)
            backgroundImage
                .opacity(isColourBackground ? 1 : backgroundAlpha)
        }
    }

    /// The opacity of the background — upstream `Config.bgAlpha`.
    private var backgroundAlpha: Double {
        ReaderBackground.alpha(for: preset)
    }

    /// Whether the background of the current mode is a colour — upstream
    /// `Config.bgType` (0: a colour, 1: an asset image, 2: another image).
    private var isColourBackground: Bool {
        preset.backgroundType(for: mode) == .color
    }

    @ViewBuilder
    private var backgroundImage: some View {
        // SwiftUI has no cross-platform image initialiser — `Image(uiImage:)`
        // on iOS and `Image(nsImage:)` on macOS.
        #if canImport(UIKit)
        if preset.backgroundType(for: mode) != .color {
            if let data = loader.data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        #elseif canImport(AppKit)
        if preset.backgroundType(for: mode) != .color {
            if let data = loader.data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        #endif
    }

    /// Loads the background file when the preset points at one.
    public func loadIfNeeded() {
        guard preset.backgroundType(for: mode) != .color else { return }
        let value = preset.backgroundString(for: mode)
        loader.load(path: ReaderBackground.filePath(for: value, root: root).path)
    }
}
