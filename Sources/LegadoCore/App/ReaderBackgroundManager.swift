import Foundation

/// The manager of the reader background presets — upstream
/// `ReadBookConfig` (the "排版" presets of `assets/defaultData/readConfig.json`).
public final class ReaderBackgroundManager {

    /// The name of the file the presets are stored in.
    public static let configFileName = "readConfig.json"

    /// The presets.
    public private(set) var presets: [ReaderBackgroundPreset]
    /// The index of the selected preset.
    public private(set) var selectedIndex: Int

    private let fileURL: URL?

    /// Creates a manager.
    ///
    /// - Parameters:
    ///   - presets: the presets; the upstream default is used when `nil`.
    ///   - selectedIndex: the index of the selected preset.
    ///   - fileURL: the file the presets are persisted in; without it they
    ///     are not persisted (the tests use that).
    public init(
        presets: [ReaderBackgroundPreset]? = nil,
        selectedIndex: Int = 0,
        fileURL: URL? = nil
    ) {
        self.presets = presets ?? [ReaderBackgroundPreset.weixinRead]
        self.selectedIndex = min(max(0, selectedIndex), max(0, self.presets.count - 1))
        self.fileURL = fileURL
        if let fileURL, let loaded = ReaderBackgroundManager.loadPresets(from: fileURL), !loaded.isEmpty {
            self.presets = loaded
        }
    }

    /// The selected preset.
    public var current: ReaderBackgroundPreset {
        guard presets.indices.contains(selectedIndex) else { return ReaderBackgroundPreset.weixinRead }
        return presets[selectedIndex]
    }

    /// Selects a preset — upstream `ReadBookConfig.selectConfig`.
    public func select(index: Int) {
        guard presets.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Adds a preset.
    public func add(_ preset: ReaderBackgroundPreset) -> Bool {
        presets.append(preset)
        selectedIndex = presets.count - 1
        return true
    }

    /// Removes a preset.
    public func delete(index: Int) {
        guard presets.indices.contains(index) else { return }
        presets.remove(at: index)
        selectedIndex = min(selectedIndex, max(0, presets.count - 1))
    }

    /// Persists the presets.
    public func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(presets) else { return }
        try? data.write(to: fileURL)
    }

    /// Loads the presets from a file.
    public static func loadPresets(from fileURL: URL) -> [ReaderBackgroundPreset]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([ReaderBackgroundPreset].self, from: data)
    }
}
