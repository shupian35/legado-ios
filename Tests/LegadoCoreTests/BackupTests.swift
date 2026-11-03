import XCTest

@testable import LegadoCore

final class BackupTests: XCTestCase {

    private var store: MemoryTableStore!

    override func setUp() {
        super.setUp()
        store = MemoryTableStore()
        try? store.createSchema()
    }

    // MARK: - Row encoding

    func testRowsRoundTripThroughJSON() throws {
        let rows: [StorageRow] = [
            ["bookUrl": .text("https://a/1"), "name": .text("书一"), "index": .integer(7), "isVip": .integer(0)],
            ["bookUrl": .text("https://a/2"), "name": .text("引号\"与\n换行"), "index": .integer(3)]
        ]
        let text = try LegadoBackup.encodeRows(rows)
        let decoded = try LegadoBackup.decodeRows(text)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0]["name"], .text("书一"))
        XCTAssertEqual(decoded[0]["index"], .integer(7))
        XCTAssertEqual(decoded[1]["name"], .text("引号\"与\n换行"))
        XCTAssertEqual(decoded[1]["bookUrl"], .text("https://a/2"))
    }

    func testEmptyAndInvalidDocuments() throws {
        XCTAssertEqual(try LegadoBackup.decodeRows("").count, 0)
        XCTAssertThrowsError(try LegadoBackup.decodeRows("{\"a\":1}"))
    }

    // MARK: - Archive

    func testBackupWritesOnlyNonEmptyTables() throws {
        try insertBook(url: "https://a/1", name: "书一")
        let archive = try LegadoBackup.make(store: store, settings: BackupSettings())
        let names = Set(archive.files.map { $0.name })
        XCTAssertTrue(names.contains("bookshelf.json"))
        XCTAssertFalse(names.contains("bookSource.json"), "an empty table must not be written")
        XCTAssertTrue(names.contains(LegadoBackup.preferencesFileName))
    }

    func testArchiveFileNameUsesDateAndDevice() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        var settings = BackupSettings(deviceName: "iPhone")
        let name = LegadoBackup.fileName(date: date, settings: settings)
        XCTAssertTrue(name.hasPrefix("backup2023-11-"))
        XCTAssertTrue(name.hasSuffix("-iPhone.zip"))

        settings.onlyLatestBackup = true
        XCTAssertEqual(LegadoBackup.fileName(date: date, settings: settings), "backup.zip")
    }

    func testArchiveFileNameStripsIllegalCharacters() {
        let settings = BackupSettings(deviceName: "a/b:c")
        let name = LegadoBackup.fileName(date: Date(timeIntervalSince1970: 1_700_000_000), settings: settings)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
    }

    // MARK: - Restore

    func testRestoreRoundTrip() throws {
        try insertBook(url: "https://a/1", name: "书一")
        try store.insert(
            ["bookSourceUrl": .text("https://s/1"), "bookSourceName": .text("源一")],
            into: "book_sources"
        )
        let archive = try LegadoBackup.make(store: store, settings: BackupSettings())
        let zip = try archive.zip()

        let fresh = MemoryTableStore()
        try fresh.createSchema()
        let summary = try LegadoBackup.restore(zipData: zip, store: fresh, settings: BackupSettings())
        XCTAssertEqual(summary.tables["books"], 1)
        XCTAssertEqual(summary.tables["book_sources"], 1)
        XCTAssertEqual(try fresh.allRows(in: "books").first?["name"], .text("书一"))
        XCTAssertEqual(try fresh.allRows(in: "book_sources").first?["bookSourceName"], .text("源一"))
    }

    func testRestoreMergesBooksInsteadOfReplacingThem() throws {
        try insertBook(url: "https://a/1", name: "远程书")
        let archive = try LegadoBackup.make(store: store, settings: BackupSettings())

        let local = MemoryTableStore()
        try local.createSchema()
        try local.insert(["bookUrl": .text("https://a/local"), "name": .text("本地书")], into: "books")

        let summary = try LegadoBackup.restore(archive, store: local, settings: BackupSettings())
        XCTAssertEqual(summary.tables["books"], 1)
        XCTAssertEqual(try local.allRows(in: "books").count, 2, "a merge must keep the local book")
    }

    func testRestoreSkipsLocalBooksWhenAsked() throws {
        try insertBook(url: "local:/sdcard/a.txt", name: "本地书", origin: "local:/sdcard")
        try insertBook(url: "https://a/1", name: "网络书")
        let archive = try LegadoBackup.make(store: store, settings: BackupSettings())

        let local = MemoryTableStore()
        try local.createSchema()
        let summary = try LegadoBackup.restore(
            archive,
            store: local,
            settings: BackupSettings(ignoreLocalBook: true)
        )
        XCTAssertEqual(summary.tables["books"], 1)
        XCTAssertEqual(try local.allRows(in: "books").first?["name"], .text("网络书"))
    }

    func testReadRecordKeepsTheNewerRow() throws {
        try store.insert(
            [
                "deviceId": .text("dev"), "bookName": .text("书一"),
                "readTime": .integer(2000), "lastRead": .integer(5)
            ],
            into: "readRecord"
        )
        let archive = try LegadoBackup.make(store: store, settings: BackupSettings())

        let local = MemoryTableStore()
        try local.createSchema()
        try local.insert(
            [
                "deviceId": .text("dev"), "bookName": .text("书一"),
                "readTime": .integer(3000), "lastRead": .integer(9)
            ],
            into: "readRecord"
        )

        let summary = try LegadoBackup.restore(archive, store: local, settings: BackupSettings())
        XCTAssertEqual(summary.tables["readRecord"], 0, "an older remote row must not win")
        XCTAssertEqual(try local.allRows(in: "readRecord").first?["lastRead"], .integer(9))
    }

    // MARK: - servers.json encryption

    func testServersAreEncryptedAndRestored() throws {
        try store.insert(
            ["id": .integer(1), "name": .text("坚果云"), "type": .text("WEBDAV"), "url": .text("https://dav/")],
            into: "servers"
        )
        let settings = BackupSettings(password: "legado")
        let archive = try LegadoBackup.make(store: store, settings: settings)
        let servers = try XCTUnwrap(archive.files.first { $0.name == "servers.json" })
        XCTAssertFalse(servers.string.hasPrefix("["), "servers.json must be encrypted")
        // It must decrypt with the same password.
        let plain = try settings.cipher.decrypt(servers.string)
        XCTAssertTrue(plain.hasPrefix("["))

        let fresh = MemoryTableStore()
        try fresh.createSchema()
        try LegadoBackup.restore(archive, store: fresh, settings: settings)
        XCTAssertEqual(try fresh.allRows(in: "servers").first?["name"], .text("坚果云"))
    }

    func testPlainServersJSONIsAccepted() throws {
        let local = MemoryTableStore()
        try local.createSchema()
        let archive = BackupArchive(fileName: "b.zip", files: [
            BackupFile(name: "servers.json", string: "[{\"id\":1,\"name\":\"旧版\"}]")
        ])
        let summary = try LegadoBackup.restore(archive, store: local, settings: BackupSettings())
        XCTAssertEqual(summary.tables["servers"], 1)
        XCTAssertEqual(try local.allRows(in: "servers").first?["name"], .text("旧版"))
    }

    // MARK: - Preferences

    func testPreferencesRoundTrip() throws {
        let preferences = ["webDavPassword": "p&ss<", "themeMode": "1"]
        let xml = LegadoBackup.encodePreferences(preferences)
        XCTAssertTrue(xml.contains("<map>"))
        let decoded = try LegadoBackup.decodePreferences(xml)
        XCTAssertEqual(decoded, preferences)
    }

    func testPreferencesAreCarriedInTheArchive() throws {
        try insertBook(url: "https://a/1", name: "书一")
        let archive = try LegadoBackup.make(
            store: store,
            settings: BackupSettings(),
            preferences: ["themeMode": "2"]
        )
        XCTAssertEqual(try LegadoBackup.preferences(in: archive), ["themeMode": "2"])
    }

    func testUnknownFilesAreReported() throws {
        try insertBook(url: "https://a/1", name: "书一")
        let archive = try LegadoBackup.make(
            store: store,
            settings: BackupSettings(),
            extraFiles: [BackupFile(name: "readConfig.json", string: "{}")]
        )
        let fresh = MemoryTableStore()
        try fresh.createSchema()
        let summary = try LegadoBackup.restore(archive, store: fresh, settings: BackupSettings())
        XCTAssertEqual(summary.skipped, ["readConfig.json"])
    }

    // MARK: - Helpers

    private func insertBook(url: String, name: String, origin: String? = nil) throws {
        var row: StorageRow = ["bookUrl": .text(url), "name": .text(name)]
        if let origin { row["origin"] = .text(origin) }
        try store.insert(row, into: "books")
    }
}
