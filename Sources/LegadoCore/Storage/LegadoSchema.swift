//
//  LegadoSchema.swift
//  LegadoCore
//
//  The database schema, ported from the Room export
//  `app/schemas/io.legado.app.data.AppDatabase/75.json` (version 75).
//
//  The table and column names are kept identical to the upstream schema so a
//  backup produced by the Android app can be restored on iOS and vice versa.
//

import Foundation

/// The type of a column.
public enum StorageColumnType: String {
    case integer = "INTEGER"
    case real = "REAL"
    case text = "TEXT"
    case blob = "BLOB"
}

/// A column of a table.
public struct ColumnDefinition: Equatable {
    public let name: String
    public let type: StorageColumnType
    public let notNull: Bool
    public let defaultValue: StorageValue?

    public init(name: String, type: StorageColumnType, notNull: Bool = false, defaultValue: StorageValue? = nil) {
        self.name = name
        self.type = type
        self.notNull = notNull
        self.defaultValue = defaultValue
    }
}

/// A foreign key of the schema — upstream `ForeignKey` in the Room schema.
public struct ForeignKeyDefinition: Equatable {
    /// The referenced table.
    public let table: String
    /// The columns of this table that form the key.
    public let columns: [String]
    /// The referenced columns of `table`.
    public let referencedColumns: [String]
    /// The `ON DELETE` action — upstream uses `CASCADE`.
    public let onDelete: String
    /// The `ON UPDATE` action — upstream uses `NO ACTION`.
    public let onUpdate: String

    public init(
        table: String,
        columns: [String],
        referencedColumns: [String],
        onDelete: String = "CASCADE",
        onUpdate: String = "NO ACTION"
    ) {
        self.table = table
        self.columns = columns
        self.referencedColumns = referencedColumns
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }

    /// The `FOREIGN KEY` clause of the key.
    public var clause: String {
        "FOREIGN KEY (\(columns.map { "\"\($0)\"" }.joined(separator: ", "))) "
            + "REFERENCES \"\(table)\" (\(referencedColumns.map { "\"\($0)\"" }.joined(separator: ", "))) "
            + "ON UPDATE \(onUpdate) ON DELETE \(onDelete)"
    }
}

/// A table of the schema.
public struct TableDefinition: Equatable {
    public let name: String
    public let columns: [ColumnDefinition]
    public let primaryKey: [String]
    /// Unique column groups, in the order upstream declares them.
    public let uniqueKeys: [[String]]
    /// Non unique index column groups.
    public let indexes: [[String]]
    /// The foreign keys of the table.
    public let foreignKeys: [ForeignKeyDefinition]

    public init(
        name: String,
        columns: [ColumnDefinition],
        primaryKey: [String],
        uniqueKeys: [[String]] = [],
        indexes: [[String]] = [],
        foreignKeys: [ForeignKeyDefinition] = []
    ) {
        self.name = name
        self.columns = columns
        self.primaryKey = primaryKey
        self.uniqueKeys = uniqueKeys
        self.indexes = indexes
        self.foreignKeys = foreignKeys
    }

    /// The `CREATE TABLE` statement of the table.
    public var createStatement: String {
        let parts = columns.map { column in
            var text = "\"\(column.name)\" \(column.type.rawValue)"
            if column.notNull { text += " NOT NULL" }
            if let value = column.defaultValue {
                text += " DEFAULT \(value.sqlLiteral)"
            }
            return text
        }
        let key = primaryKey.isEmpty ? "" : ", PRIMARY KEY (\(primaryKey.map { "\"\($0)\"" }.joined(separator: ", ")))"
        let keys = foreignKeys.map { ", \($0.clause)" }.joined()
        return "CREATE TABLE IF NOT EXISTS \"\(name)\" (\(parts.joined(separator: ", "))\(key)\(keys))"
    }

    /// The `CREATE INDEX` statements of the table.
    public var createIndexStatements: [String] {
        var statements: [String] = []
        for group in uniqueKeys {
            // The local name must not shadow `name`: the index is created on
            // the *table* `name`, and shadowing it produced
            // `CREATE INDEX "index_…" ON "index_…"`, which SQLite rejects with
            // "no such table" — and the schema creation stopped there.
            let indexName = "index_\(name)_\(group.joined(separator: "_"))"
            statements.append(
                "CREATE UNIQUE INDEX IF NOT EXISTS \"\(indexName)\" ON \"\(name)\" (\(group.map { "\"\($0)\"" }.joined(separator: ", ")))"
            )
        }
        for group in indexes {
            let indexName = "index_\(name)_\(group.joined(separator: "_"))"
            statements.append(
                "CREATE INDEX IF NOT EXISTS \"\(indexName)\" ON \"\(name)\" (\(group.map { "\"\($0)\"" }.joined(separator: ", ")))"
            )
        }
        return statements
    }
}

extension StorageValue {
    /// The SQL literal of the value.
    public var sqlLiteral: String {
        switch self {
        case .null: return "NULL"
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        case .text(let value): return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
        case .blob: return "X''"
        }
    }
}

/// The schema of the Legado database — Room version 75.
public enum LegadoSchema {
    /// The upstream schema version.
    public static let version = 75

    /// The default book groups upstream seeds on first launch.
    ///
    /// Upstream `AppDatabase.dbCallback.onCreate` inserts six rows with
    /// `insert … select <groupId>, '<groupName>', <order>, <show> [,<enableRefresh>]
    /// where not exists (…)`. The `order` column is only the display order —
    /// the group id is the negative "well known" id of upstream.
    public struct DefaultGroup {
        public let id: Int64
        public let name: String
        public let order: Int64
        public let enableRefresh: Bool
        public let show: Bool

        public init(id: Int64, name: String, order: Int64, enableRefresh: Bool = true, show: Bool = true) {
            self.id = id
            self.name = name
            self.order = order
            self.enableRefresh = enableRefresh
            self.show = show
        }
    }

    public static let defaultGroups: [DefaultGroup] = [
        DefaultGroup(id: BookGroup.Id.all, name: "全部", order: -10),
        DefaultGroup(id: BookGroup.Id.local, name: "本地", order: -9, enableRefresh: false),
        DefaultGroup(id: BookGroup.Id.audio, name: "音频", order: -8),
        DefaultGroup(id: BookGroup.Id.netNoGroup, name: "网络未分组", order: -7),
        DefaultGroup(id: BookGroup.Id.localNoGroup, name: "本地未分组", order: -6, enableRefresh: false, show: false),
        DefaultGroup(id: BookGroup.Id.updateError, name: "更新失败", order: -1)
    ]

    private static func text(_ name: String, notNull: Bool = false) -> ColumnDefinition {
        ColumnDefinition(name: name, type: .text, notNull: notNull)
    }

    private static func integer(_ name: String, notNull: Bool = true, default defaultValue: StorageValue? = nil) -> ColumnDefinition {
        ColumnDefinition(name: name, type: .integer, notNull: notNull, defaultValue: defaultValue)
    }

    /// Every table of the schema, in creation order.
    public static let tables: [TableDefinition] = [
        TableDefinition(
            name: "books",
            columns: [
                text("bookUrl", notNull: true),
                text("tocUrl", notNull: true),
                text("origin", notNull: true),
                text("originName", notNull: true),
                text("name", notNull: true),
                text("author", notNull: true),
                text("kind"),
                text("customTag"),
                text("coverUrl"),
                text("customCoverUrl"),
                text("intro"),
                text("customIntro"),
                text("charset"),
                integer("type"),
                integer("group"),
                text("latestChapterTitle"),
                integer("latestChapterTime"),
                integer("lastCheckTime"),
                integer("lastCheckCount"),
                integer("totalChapterNum"),
                text("durChapterTitle"),
                integer("durChapterIndex"),
                integer("durChapterPos"),
                integer("durChapterTime"),
                text("wordCount"),
                integer("canUpdate"),
                integer("order"),
                integer("originOrder"),
                text("variable"),
                text("readConfig"),
                integer("syncTime")
            ],
            primaryKey: ["bookUrl"],
            uniqueKeys: [["name", "author"]]
        ),
        TableDefinition(
            name: "book_groups",
            columns: [
                integer("groupId"),
                text("groupName", notNull: true),
                text("cover"),
                integer("order"),
                integer("enableRefresh"),
                integer("show"),
                integer("bookSort")
            ],
            primaryKey: ["groupId"]
        ),
        TableDefinition(
            name: "book_sources",
            columns: [
                text("bookSourceUrl", notNull: true),
                text("bookSourceName", notNull: true),
                text("bookSourceGroup"),
                integer("bookSourceType"),
                text("bookUrlPattern"),
                integer("customOrder"),
                integer("enabled"),
                integer("enabledExplore"),
                text("jsLib"),
                integer("enabledCookieJar", notNull: false),
                text("concurrentRate"),
                text("header"),
                text("loginUrl"),
                text("loginUi"),
                text("loginCheckJs"),
                text("coverDecodeJs"),
                text("bookSourceComment"),
                text("variableComment"),
                integer("lastUpdateTime"),
                integer("respondTime"),
                integer("weight"),
                text("exploreUrl"),
                text("exploreScreen"),
                text("ruleExplore"),
                text("searchUrl"),
                text("ruleSearch"),
                text("ruleBookInfo"),
                text("ruleToc"),
                text("ruleContent"),
                text("ruleReview")
            ],
            primaryKey: ["bookSourceUrl"]
        ),
        TableDefinition(
            name: "chapters",
            columns: [
                text("url", notNull: true),
                text("title", notNull: true),
                integer("isVolume"),
                text("baseUrl", notNull: true),
                text("bookUrl", notNull: true),
                integer("index"),
                integer("isVip"),
                integer("isPay"),
                text("resourceUrl"),
                text("tag"),
                text("wordCount"),
                integer("start", notNull: false),
                integer("end", notNull: false),
                text("startFragmentId"),
                text("endFragmentId"),
                text("variable")
            ],
            primaryKey: ["url", "bookUrl"],
            uniqueKeys: [["bookUrl", "index"]],
            indexes: [["bookUrl"]],
            foreignKeys: [
                ForeignKeyDefinition(
                    table: "books",
                    columns: ["bookUrl"],
                    referencedColumns: ["bookUrl"]
                )
            ]
        ),
        TableDefinition(
            name: "replace_rules",
            columns: [
                integer("id"),
                text("name", notNull: true),
                text("group"),
                text("pattern", notNull: true),
                text("replacement", notNull: true),
                text("scope"),
                integer("scopeTitle"),
                integer("scopeContent"),
                text("excludeScope"),
                integer("isEnabled"),
                integer("isRegex"),
                integer("timeoutMillisecond"),
                integer("sortOrder")
            ],
            primaryKey: ["id"]
        ),
        TableDefinition(
            name: "searchBooks",
            columns: [
                text("bookUrl", notNull: true),
                text("origin", notNull: true),
                text("originName", notNull: true),
                integer("type"),
                text("name", notNull: true),
                text("author", notNull: true),
                text("kind"),
                text("coverUrl"),
                text("intro"),
                text("wordCount"),
                text("latestChapterTitle"),
                text("tocUrl", notNull: true),
                integer("time"),
                text("variable"),
                integer("originOrder"),
                text("chapterWordCountText"),
                integer("chapterWordCount"),
                integer("respondTime")
            ],
            primaryKey: ["bookUrl"],
            uniqueKeys: [["bookUrl"]],
            indexes: [["origin"]],
            foreignKeys: [
                ForeignKeyDefinition(
                    table: "book_sources",
                    columns: ["origin"],
                    referencedColumns: ["bookSourceUrl"]
                )
            ]
        ),
        TableDefinition(
            name: "search_keywords",
            columns: [
                text("word", notNull: true),
                integer("usage"),
                integer("lastUseTime")
            ],
            primaryKey: ["word"],
            uniqueKeys: [["word"]]
        ),
        TableDefinition(
            name: "cookies",
            columns: [
                text("url", notNull: true),
                text("cookie", notNull: true)
            ],
            primaryKey: ["url"],
            uniqueKeys: [["url"]]
        ),
        TableDefinition(
            name: "rssSources",
            columns: [
                text("sourceUrl", notNull: true),
                text("sourceName", notNull: true),
                text("sourceIcon", notNull: true),
                text("sourceGroup"),
                text("sourceComment"),
                integer("enabled"),
                text("variableComment"),
                text("jsLib"),
                integer("enabledCookieJar", notNull: false),
                text("concurrentRate"),
                text("header"),
                text("loginUrl"),
                text("loginUi"),
                text("loginCheckJs"),
                text("coverDecodeJs"),
                text("sortUrl"),
                integer("singleUrl"),
                integer("articleStyle"),
                text("ruleArticles"),
                text("ruleNextPage"),
                text("ruleTitle"),
                text("rulePubDate"),
                text("ruleDescription"),
                text("ruleImage"),
                text("ruleLink"),
                text("ruleContent"),
                text("contentWhitelist"),
                text("contentBlacklist"),
                text("shouldOverrideUrlLoading"),
                text("style"),
                integer("enableJs"),
                integer("loadWithBaseUrl"),
                text("injectJs"),
                integer("lastUpdateTime"),
                integer("customOrder")
            ],
            primaryKey: ["sourceUrl"]
        ),
        TableDefinition(
            name: "bookmarks",
            columns: [
                integer("time"),
                text("bookName", notNull: true),
                text("bookAuthor", notNull: true),
                integer("chapterIndex"),
                integer("chapterPos"),
                text("chapterName", notNull: true),
                text("bookText", notNull: true),
                text("content", notNull: true)
            ],
            primaryKey: ["time"],
            indexes: [["bookName", "bookAuthor"]]
        ),
        TableDefinition(
            name: "rssArticles",
            columns: [
                text("origin", notNull: true),
                text("sort", notNull: true),
                text("title", notNull: true),
                integer("order"),
                text("link", notNull: true),
                text("pubDate"),
                text("description"),
                text("content"),
                text("image"),
                text("group", notNull: true),
                integer("read"),
                text("variable")
            ],
            primaryKey: ["origin", "link"]
        ),
        TableDefinition(
            name: "rssReadRecords",
            columns: [
                text("record", notNull: true),
                text("title"),
                integer("readTime", notNull: false),
                integer("read")
            ],
            primaryKey: ["record"]
        ),
        TableDefinition(
            name: "rssStars",
            columns: [
                text("origin", notNull: true),
                text("sort", notNull: true),
                text("title", notNull: true),
                integer("starTime"),
                text("link", notNull: true),
                text("pubDate"),
                text("description"),
                text("content"),
                text("image"),
                text("group", notNull: true),
                text("variable")
            ],
            primaryKey: ["origin", "link"]
        ),
        TableDefinition(
            name: "txtTocRules",
            columns: [
                integer("id"),
                text("name", notNull: true),
                text("rule", notNull: true),
                text("example"),
                integer("serialNumber"),
                integer("enable")
            ],
            primaryKey: ["id"]
        ),
        TableDefinition(
            name: "readRecord",
            columns: [
                text("deviceId", notNull: true),
                text("bookName", notNull: true),
                integer("readTime"),
                integer("lastRead")
            ],
            primaryKey: ["deviceId", "bookName"]
        ),
        TableDefinition(
            name: "httpTTS",
            columns: [
                integer("id"),
                text("name", notNull: true),
                text("url", notNull: true),
                text("contentType"),
                text("concurrentRate"),
                text("loginUrl"),
                text("loginUi"),
                text("header"),
                text("jsLib"),
                integer("enabledCookieJar", notNull: false),
                text("loginCheckJs"),
                integer("lastUpdateTime")
            ],
            primaryKey: ["id"]
        ),
        TableDefinition(
            name: "caches",
            columns: [
                text("key", notNull: true),
                text("value"),
                integer("deadline")
            ],
            primaryKey: ["key"],
            uniqueKeys: [["key"]]
        ),
        TableDefinition(
            name: "ruleSubs",
            columns: [
                integer("id"),
                text("name", notNull: true),
                text("url", notNull: true),
                integer("type"),
                integer("customOrder"),
                integer("autoUpdate"),
                integer("update")
            ],
            primaryKey: ["id"]
        ),
        TableDefinition(
            name: "dictRules",
            columns: [
                text("name", notNull: true),
                text("urlRule", notNull: true),
                text("showRule", notNull: true),
                integer("enabled"),
                integer("sortNumber")
            ],
            primaryKey: ["name"]
        ),
        TableDefinition(
            name: "keyboardAssists",
            columns: [
                integer("type"),
                text("key", notNull: true),
                text("value", notNull: true),
                integer("serialNo")
            ],
            primaryKey: ["type", "key"]
        ),
        TableDefinition(
            name: "servers",
            columns: [
                integer("id"),
                text("name", notNull: true),
                text("type", notNull: true),
                text("config"),
                integer("sortNumber")
            ],
            primaryKey: ["id"]
        )
    ]

    /// The table definition of a table.
    public static func table(_ name: String) -> TableDefinition? {
        tables.first { $0.name == name }
    }
}
