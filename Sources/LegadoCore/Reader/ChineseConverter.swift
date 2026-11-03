//
//  ChineseConverter.swift
//  LegadoCore
//
//  The port of `io.legado.app.utils.ChineseUtils`.
//
//  Upstream: app/src/main/java/io/legado/app/utils/ChineseUtils.kt
//

import Foundation

/// Converts Chinese text between the simplified and the traditional script.
///
/// The upstream uses the `quick-transfer` library, whose dictionaries are
/// OpenCC derived; the port ships the same tables
/// (`Reader/ChineseCharacters.swift` and `Reader/ChinesePhrases.swift`,
/// generated from the OpenCC data files by
/// `Scripts/gen_chinese_table.py`).
///
/// The upstream also excludes a list of words whose traditional form is a
/// different, valid word (`ChineseUtils.fixT2sDict`) — the port reproduces it.
public enum ChineseConverter {

    // MARK: - The excluded words

    /// The words that must not be converted — upstream `ChineseUtils.fixT2sDict`.
    ///
    /// The upstream loads this list into the traditional → simplified
    /// dictionary only, so the simplified → traditional direction converts
    /// them.
    public static let excludedTraditionalWords: [String] = [
        "槃",
        "划槳", "列根", "雪梨", "雪糕", "多士", "起司", "芝士", "沙芬", "母音",
        "华乐", "民乐", "晶元", "晶片", "映像", "明覆", "明瞭", "新力", "新喻",
        "零錢", "零钱", "離線", "碟片", "模組", "桌球", "案頭", "機車", "電漿",
        "鳳梨", "魔戒", "載入", "菲林", "整合", "變數", "解碼", "散钱", "插水",
        "房屋", "房价", "快取", "德士", "建立", "常式", "席丹", "布殊", "布希",
        "巴哈", "巨集", "夜学", "向量", "半形", "加彭", "列印", "函式", "全形",
        "光碟", "介面", "乳酪", "沈船", "永珍", "演化", "牛油", "相容", "磁碟",
        "菲林", "規則", "酵素", "雷根", "饭盒",
        "路易斯", "非同步", "出租车", "周杰倫", "马铃薯", "馬鈴薯", "機械人", "電單車",
        "電扶梯", "音效卡", "飆車族", "點陣圖", "個入球", "顆進球", "沃尓沃", "晶片集",
        "斯瓦巴", "斜角巷", "战列舰", "快速面", "希特拉", "太空梭", "吐瓦魯", "吉布堤",
        "吉布地", "史太林", "南冰洋", "区域网", "波札那", "解析度", "酷洛米", "金夏沙",
        "魔獸紀元", "高空彈跳", "铁达尼号", "太空战士", "埃及妖后", "吉里巴斯", "附加元件",
        "魔鬼終結者", "純文字檔案", "奇幻魔法Melody", "列支敦斯登"
    ]

    // MARK: - The conversion

    /// Traditional → simplified — upstream `ChineseUtils.t2s`.
    public static func toSimplified(_ text: String) -> String {
        convert(
            text,
            map: traditionalToSimplified,
            phrases: traditionalToSimplifiedPhrases,
            protectedWords: excludedTraditionalWords
        )
    }

    /// Simplified → traditional — upstream `ChineseUtils.s2t`.
    public static func toTraditional(_ text: String) -> String {
        convert(
            text,
            map: simplifiedToTraditional,
            phrases: simplifiedToTraditionalPhrases,
            protectedWords: []
        )
    }

    /// Converts the text with the given mode — upstream
    /// `ContentProcessor`'s `when (AppConfig.chineseConverterType)`.
    public static func convert(_ text: String, mode: ChineseConversionMode) -> String {
        switch mode {
        case .off: return text
        case .traditionalToSimplified: return toSimplified(text)
        case .simplifiedToTraditional: return toTraditional(text)
        }
    }

    // MARK: - The tables

    /// The traditional → simplified character map.
    static let traditionalToSimplified: [Character: Character] = buildMap(
        ChineseCharacters.traditionalToSimplifiedSource,
        ChineseCharacters.traditionalToSimplifiedTarget
    )

    /// The simplified → traditional character map.
    static let simplifiedToTraditional: [Character: Character] = buildMap(
        ChineseCharacters.simplifiedToTraditionalSource,
        ChineseCharacters.simplifiedToTraditionalTarget
    )

    /// The traditional → simplified phrase table.
    static let traditionalToSimplifiedPhrases = PhraseTable(
        ChinesePhrases.traditionalToSimplified
    )

    /// The simplified → traditional phrase table.
    static let simplifiedToTraditionalPhrases = PhraseTable(
        ChinesePhrases.simplifiedToTraditional
    )

    private static func buildMap(_ source: String, _ target: String) -> [Character: Character] {
        let sourceCharacters = Array(source)
        let targetCharacters = Array(target)
        var map: [Character: Character] = [:]
        let count = min(sourceCharacters.count, targetCharacters.count)
        for index in 0..<count {
            map[sourceCharacters[index]] = targetCharacters[index]
        }
        return map
    }

    // MARK: - The conversion itself

    private static func convert(
        _ text: String,
        map: [Character: Character],
        phrases: PhraseTable,
        protectedWords: [String]
    ) -> String {
        guard !map.isEmpty, !text.isEmpty else { return text }
        let characters = Array(text)
        let protected = protectedIndices(in: characters, words: protectedWords)
        var output = ""
        output.reserveCapacity(text.count)
        var index = 0
        while index < characters.count {
            if protected.contains(index) {
                output.append(characters[index])
                index += 1
                continue
            }
            // The phrases win over the single characters (upstream OpenCC
            // converts the phrases first).
            if let match = phrases.match(characters, at: index) {
                output.append(contentsOf: match.value)
                index += match.length
                continue
            }
            if let replacement = map[characters[index]] {
                output.append(replacement)
            } else {
                output.append(characters[index])
            }
            index += 1
        }
        return output
    }

    /// The indices of the characters that belong to one of the protected words.
    private static func protectedIndices(
        in characters: [Character],
        words: [String]
    ) -> Set<Int> {
        var protected: Set<Int> = []
        guard !words.isEmpty else { return protected }
        for word in words {
            let needle = Array(word)
            guard needle.count > 1 else { continue }
            guard characters.count >= needle.count else { continue }
            var start = 0
            while start + needle.count <= characters.count {
                var matched = true
                for offset in 0..<needle.count where characters[start + offset] != needle[offset] {
                    matched = false
                    break
                }
                if matched {
                    for offset in 0..<needle.count {
                        protected.insert(start + offset)
                    }
                    start += needle.count
                } else {
                    start += 1
                }
            }
        }
        return protected
    }
}

/// A parsed phrase table — upstream OpenCC matches the longest phrase first.
public struct PhraseTable: @unchecked Sendable {

    /// A matched phrase.
    public struct Match: Equatable {
        /// The replacement text.
        public let value: String
        /// The length of the matched key, in characters.
        public let length: Int
    }

    private let entries: [String: String]
    private let maxLength: Int

    /// Parses the `key\tvalue` table.
    public init(_ data: String) {
        var entries: [String: String] = [:]
        var maxLength = 0
        for line in data.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let key = String(line[line.startIndex..<tab])
            let value = String(line[line.index(after: tab)...])
            guard !key.isEmpty, !value.isEmpty else { continue }
            entries[key] = value
            maxLength = max(maxLength, key.count)
        }
        self.entries = entries
        self.maxLength = maxLength
    }

    /// The number of the entries.
    public var count: Int { entries.count }

    /// The longest key of the table.
    public var longestKey: Int { maxLength }

    /// Matches the longest phrase at the given position.
    public func match(_ characters: [Character], at index: Int) -> Match? {
        guard !entries.isEmpty, index < characters.count else { return nil }
        let limit = min(maxLength, characters.count - index)
        if limit > 0, let value = entries[String(characters[index..<(index + limit)])] {
            return Match(value: value, length: limit)
        }
        var length = limit - 1
        while length > 0 {
            if let value = entries[String(characters[index..<(index + length)])] {
                return Match(value: value, length: length)
            }
            length -= 1
        }
        return nil
    }
}

/// The default converter — upstream uses the static `ChineseUtils`.
public final class DefaultChineseConverter: ChineseConverting {
    public init() {}
    public func toSimplified(_ text: String) -> String { ChineseConverter.toSimplified(text) }
    public func toTraditional(_ text: String) -> String { ChineseConverter.toTraditional(text) }
}

extension ChineseConverter: ChineseConverting {
    public func toSimplified(_ text: String) -> String { ChineseConverter.toSimplified(text) }
    public func toTraditional(_ text: String) -> String { ChineseConverter.toTraditional(text) }
}
