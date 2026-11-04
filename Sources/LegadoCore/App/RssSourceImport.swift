//
//  RssSourceImport.swift
//  LegadoCore
//
//  The import of the RSS sources.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/association/ImportRssSourceViewModel.kt
//

import Foundation

/// The import of the RSS sources — upstream `ImportRssSourceViewModel`.
///
/// The upstream accepts
///
/// * a JSON object with a `sourceUrls` member — the URLs are downloaded,
/// * a JSON array of `RssSource` objects,
/// * a single `RssSource` object,
/// * an absolute URL — the document is downloaded and parsed,
/// * the content of a local file.
public enum RssSourceImport {

    /// The errors of the import.
    public enum ImportError: Error, Equatable {
        /// The document is not a JSON array of the RSS sources.
        case notAnArray
        /// The document does not hold any RSS source.
        case notAnRssSource
        /// The document is not JSON at all.
        case wrongFormat
    }

    /// The RSS sources of a JSON document — upstream
    /// `ImportRssSourceViewModel.importSourceAwait` (the JSON branches).
    ///
    /// The upstream rejects a document whose first source has an empty
    /// `sourceUrl` ("不是订阅源").
    public static func sources(json: String) throws -> [RssSource] {
        let value = try JSONValue.parse(json)
        let array: [JSONValue]
        switch value {
        case .array(let items): array = items
        case .object: array = [value]
        default: throw ImportError.wrongFormat
        }
        var sources: [RssSource] = []
        for item in array {
            if let source = RssSourceJSONBridge.decode(item) { sources.append(source) }
        }
        guard let first = sources.first else { throw ImportError.notAnRssSource }
        guard !first.sourceUrl.isEmpty else { throw ImportError.notAnRssSource }
        return sources
    }

    /// The source URLs of a JSON object with a `sourceUrls` member — upstream
    /// `ImportRssSourceViewModel.importSourceAwait` (the `sourceUrls` branch).
    public static func sourceURLs(json: String) throws -> [String] {
        let value = try JSONValue.parse(json)
        guard let object = value.objectValue,
              let urls = object["sourceUrls"]?.arrayValue else { return [] }
        return urls.compactMap { $0.stringValue }.filter { !$0.isEmpty }
    }

    /// Whether a text is an absolute URL — upstream `isAbsUrl`.
    public static func isAbsoluteURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    // MARK: - The preview of the import

    /// The state of an imported source against the local ones — upstream
    /// `ImportRssSourceViewModel.comparisonSource` (the adapter shows
    /// "新增", "更新" or "已有").
    public enum State: String, Equatable, Sendable {
        /// The source is not on the device.
        case new = "新增"
        /// The imported source is newer than the local one.
        case update = "更新"
        /// The local source is the same or newer.
        case existing = "已有"
    }

    /// The options of the import — upstream
    /// `ImportRssSourceViewModel.importSelect` and the menu
    /// `res/menu/import_source.xml` (保留名称 / 保留分组 / 保留启用 / 新建分组).
    public struct Options: Equatable, Sendable {
        /// The name of the local source wins — `importKeepName`.
        public var keepName = false
        /// The group of the local source wins — `importKeepGroup`.
        public var keepGroup = false
        /// The enabled flag of the local source wins — `importKeepEnable`.
        public var keepEnable = false
        /// The group the imported sources are put into.
        public var groupName: String? = nil
        /// The group is added to the groups of the source instead of
        /// replacing them — the upstream's "同时添加分组" switch.
        public var addGroup = false

        public init() {}
    }

    /// One source of the import preview.
    public struct Item: Identifiable, Equatable, Sendable {
        /// The imported source.
        public let source: RssSource
        /// The state against the local sources.
        public let state: State
        /// Whether the source is selected — upstream `selectStatus`.
        public var selected: Bool

        public var id: String { source.sourceUrl }

        public init(source: RssSource, state: State, selected: Bool) {
            self.source = source
            self.state = state
            self.selected = selected
        }
    }

    /// The preview of the import — upstream
    /// `ImportRssSourceViewModel.comparisonSource`.
    ///
    /// A source is selected when it is new or when it is newer than the
    /// local one (`checkSources[index] == null || has.lastUpdateTime <
    /// it.lastUpdateTime`).
    public static func items(_ sources: [RssSource], local: [RssSource]) -> [Item] {
        sources.map { source in
            guard let has = local.first(where: { $0.sourceUrl == source.sourceUrl }) else {
                return Item(source: source, state: .new, selected: true)
            }
            let state: State = has.lastUpdateTime < source.lastUpdateTime ? .update : .existing
            return Item(source: source, state: state, selected: state != .existing)
        }
    }

    /// The sources that are inserted — upstream
    /// `ImportRssSourceViewModel.importSelect`.
    ///
    /// The selected sources keep the name, the group and the enabled flag of
    /// the local source when the matching option is on; the order always
    /// comes from the local source. The group of the options is added to the
    /// groups of the source or replaces them.
    public static func prepare(
        _ items: [Item],
        local: [RssSource],
        options: Options
    ) -> [RssSource] {
        let group = options.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var prepared: [RssSource] = []
        for item in items where item.selected {
            var source = item.source
            if let has = local.first(where: { $0.sourceUrl == source.sourceUrl }) {
                if options.keepName {
                    source.sourceName = has.sourceName
                }
                if options.keepGroup {
                    source.sourceGroup = has.sourceGroup
                }
                if options.keepEnable {
                    source.enabled = has.enabled
                }
                source.customOrder = has.customOrder
            }
            if !group.isEmpty {
                if options.addGroup {
                    var groups = RssLibrary.splitGroups(source.sourceGroup)
                    if !groups.contains(group) {
                        groups.append(group)
                    }
                    source.sourceGroup = groups.joined(separator: ",")
                } else {
                    source.sourceGroup = group
                }
            }
            prepared.append(source)
        }
        return prepared
    }
}
