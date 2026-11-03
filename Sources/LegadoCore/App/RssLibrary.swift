import Foundation

/// The RSS library — the favourites, the groups and the read records.
///
/// Upstream:
/// - `ui/rss/favorites/RssFavoritesActivity.kt` — the favourites and their
///   groups (the default group is "默认分组"),
/// - `ui/rss/source/manage/RssSourceViewModel.kt` — the groups of the
///   sources (`sourceGroup` is a comma separated list),
/// - `data/dao/RssReadRecordDao.kt` — the read records (the key is the
///   article link).
public enum RssLibrary {

    /// The default group of the upstream favourites.
    public static let defaultGroup = "默认分组"

    /// A group of the RSS sources or of the favourites.
    public struct Group: Identifiable, Equatable, Sendable {
        public let name: String
        public let count: Int
        public var id: String { name }
    }

    /// The groups of the RSS sources.
    ///
    /// Upstream `sourceGroup` holds a comma separated list of group names
    /// (`RssSourceViewModel.addGroup` appends ",name").
    public static func sourceGroups(_ sources: [RssSource]) -> [Group] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for source in sources {
            for name in splitGroups(source.sourceGroup) {
                if counts[name] == nil { order.append(name) }
                counts[name, default: 0] += 1
            }
        }
        return order.map { Group(name: $0, count: counts[$0] ?? 0) }
    }

    /// The groups of the favourites.
    public static func starGroups(_ stars: [RssStar]) -> [Group] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for star in stars {
            let name = star.group.isEmpty ? defaultGroup : star.group
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { Group(name: $0, count: counts[$0] ?? 0) }
    }

    /// Splits a comma separated group list.
    public static func splitGroups(_ groups: String?) -> [String] {
        guard let groups, !groups.isEmpty else { return [] }
        return groups
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Adds a group to a source — upstream `RssSource.addGroup`.
    public static func addGroup(_ group: String, to source: inout RssSource) {
        var groups = splitGroups(source.sourceGroup)
        guard !groups.contains(group) else { return }
        groups.append(group)
        source.sourceGroup = groups.joined(separator: ",")
    }

    /// Removes a group from a source — upstream `RssSource.removeGroup`.
    public static func removeGroup(_ group: String, from source: inout RssSource) {
        let groups = splitGroups(source.sourceGroup).filter { $0 != group }
        source.sourceGroup = groups.isEmpty ? nil : groups.joined(separator: ",")
    }

    /// The star of an article, if it is starred.
    public static func star(of article: RssArticle, in stars: [RssStar]) -> RssStar? {
        stars.first { $0.link == article.link }
    }

    /// Adds or removes the star of an article.
    ///
    /// Upstream `ReadRssActivity.updateFavorite` stores the article in the
    /// `rssStars` table; the favourites are identified by the article link.
    public static func toggleStar(
        article: RssArticle,
        group: String = defaultGroup,
        in stars: [RssStar]
    ) -> (star: RssStar?, remaining: [RssStar]) {
        if let existing = stars.first(where: { $0.link == article.link }) {
            return (nil, stars.filter { $0.link != article.link })
        }
        let star = RssStar(
            origin: article.origin,
            sort: article.sort,
            title: article.title,
            link: article.link,
            starTime: Int64(Date().timeIntervalSince1970 * 1000),
            pubDate: article.pubDate,
            description: article.description,
            content: article.content,
            image: article.image,
            group: group
        )
        return (star, stars)
    }

    /// The read record of an article.
    public static func readRecord(of article: RssArticle, in records: [RssReadRecord]) -> RssReadRecord? {
        records.first { $0.record == article.link }
    }

    /// Marks an article as read — upstream `RssReadRecordDao`.
    public static func markRead(
        article: RssArticle,
        in records: [RssReadRecord]
    ) -> (record: RssReadRecord, remaining: [RssReadRecord]) {
        let record = RssReadRecord(
            record: article.link,
            title: article.title,
            readTime: Int64(Date().timeIntervalSince1970 * 1000),
            read: true
        )
        var remaining = records.filter { $0.record != article.link }
        remaining.append(record)
        return (record, remaining)
    }

    /// The articles that have not been read yet.
    public static func unread(_ articles: [RssArticle], records: [RssReadRecord]) -> [RssArticle] {
        let read = Set(records.filter { $0.read }.map(\.record))
        return articles.filter { !read.contains($0.link) }
    }
}
