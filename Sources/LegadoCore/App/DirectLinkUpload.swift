import Foundation

//
//  DirectLinkUpload.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/help/DirectLinkUpload.kt.
//
//  It uploads a file (a backup, a book) to a user configured service and
//  returns the download link that the service answered with.
//

/// The rule of the direct link upload — the upstream `DirectLinkUpload.Rule`.
public struct DirectLinkUploadRule: Codable, Equatable, Sendable {
    /// The upload address; it may carry an option block
    /// (`url,{"method":"POST","body":{"file":"fileRequest"},"type":"multipart/form-data"}`).
    public var uploadUrl: String
    /// The rule that extracts the download link from the response.
    public var downloadUrlRule: String
    /// The human readable name of the service.
    public var summary: String
    /// Whether the file is zipped before the upload.
    public var compress: Bool

    public init(uploadUrl: String, downloadUrlRule: String, summary: String, compress: Bool = false) {
        self.uploadUrl = uploadUrl
        self.downloadUrlRule = downloadUrlRule
        self.summary = summary
        self.compress = compress
    }
}

public enum DirectLinkUploadError: Error, Equatable {
    case notConfigured(String)
    case uploadFailed(String)
}

/// The direct link upload service — the port of the upstream `DirectLinkUpload`.
public enum DirectLinkUpload {

    /// The name of the rule file — the upstream `ruleFileName`.
    public static let ruleFileName = "directLinkUploadRule.json"

    /// The key the rule is stored under in the settings store.
    public static let ruleKey = "directLinkUploadRule"

    /// The upstream's default rules
    /// (`app/src/main/assets/defaultData/directLinkUpload.json`).
    public static let defaultRules: [DirectLinkUploadRule] = [
        DirectLinkUploadRule(
            uploadUrl: "https://sy.nyasama.net/shuyuan,{\"method\":\"POST\",\"body\": {\"file\": \"fileRequest\"},\"type\": \"multipart/form-data\"}",
            downloadUrlRule: "$.data@js:if (result == '') \n '' \n else \n 'https://shuyuan.nyasama.net/shuyuan/' + result",
            summary: "喵公子网盘①(有效期30天·香港G口)"
        ),
        DirectLinkUploadRule(
            uploadUrl: "https://sy.mgz6.com/shuyuan,{\"method\":\"POST\",\"body\": {\"file\": \"fileRequest\"},\"type\": \"multipart/form-data\"}",
            downloadUrlRule: "$.data@js:if (result == '') \n '' \n else \n 'https://shuyuan.mgz6.com/shuyuan/' + result",
            summary: "喵公子网盘②(有效期7天)"
        ),
        DirectLinkUploadRule(
            uploadUrl: "http://v2.jt12.eu/up-v2.php,{\"method\":\"POST\",\"body\": {\"file\": \"fileRequest\"},\"type\": \"multipart/form-data\"}",
            downloadUrlRule: "$.msg",
            summary: "橘涂书源网盘2.0 Beta(永久有效)"
        )
    ]

    /// The stored rule — the upstream `getConfig`.
    public static func getConfig(store: SettingsStore) -> DirectLinkUploadRule? {
        guard let json = store.string(forKey: ruleKey), !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(DirectLinkUploadRule.self, from: Data(json.utf8))
    }

    /// The rule in use — the upstream `getRule` (the stored one, else the first default).
    public static func getRule(store: SettingsStore) -> DirectLinkUploadRule {
        getConfig(store: store) ?? defaultRules[0]
    }

    /// Store the rule — the upstream `putConfig`.
    public static func putConfig(_ rule: DirectLinkUploadRule, store: SettingsStore) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(rule), let json = String(data: data, encoding: .utf8) {
            store.set(json, forKey: ruleKey)
        }
    }

    /// Delete the stored rule — the upstream `delConfig`.
    public static func delConfig(store: SettingsStore) {
        store.set(nil, forKey: ruleKey)
    }

    /// The name of the service — the upstream `getSummary`.
    public static func getSummary(store: SettingsStore) -> String {
        getRule(store: store).summary
    }

    /// Upload the file and return the download link — the upstream `upLoad`.
    ///
    /// The upstream zips the payload when the rule asks for it, posts it as a
    /// `multipart/form-data` body and then applies the download rule to the
    /// response body.
    public static func upload(
        fileName: String,
        file: Data,
        contentType: String,
        rule: DirectLinkUploadRule? = nil,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> String {
        let rule = rule ?? getRule(store: InMemorySettingsStore())
        if rule.uploadUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DirectLinkUploadError.notConfigured("上传url未配置")
        }
        if rule.downloadUrlRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DirectLinkUploadError.notConfigured("下载地址规则未配置")
        }

        var uploadName = fileName
        var uploadData = file
        var uploadType = contentType
        if rule.compress && contentType != "application/zip" {
            uploadName = "\(fileName).zip"
            uploadType = "application/zip"
            uploadData = try ZipWriter.archive([ZipWriteEntry(name: fileName, data: file)])
        }

        let analyzeUrl = AnalyzeUrl(url: rule.uploadUrl, dependencies: dependencies)
        let response = try await analyzeUrl.upload(
            fileName: uploadName,
            file: uploadData,
            contentType: uploadType
        )

        let box = RuleDataBox()
        let analyzeRule = AnalyzeRule()
        analyzeRule.ruleData = box
        let responseBody = response.body ?? ""
        _ = try analyzeRule.setContent(.text(responseBody))
        analyzeRule.setBaseUrl(response.url)
        let downloadUrl = try analyzeRule.getString(rule.downloadUrlRule)
        if downloadUrl.isEmpty {
            throw DirectLinkUploadError.uploadFailed("上传失败,\(responseBody)")
        }
        return downloadUrl
    }
}
