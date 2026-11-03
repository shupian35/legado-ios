//
//  AppUpdate.swift
//  LegadoCore
//
//  The application update check — the port of
//  `app/src/main/java/io/legado/app/help/update/AppUpdateGitHub.kt`.
//
//  The upstream asks the GitHub API for the latest release of
//  `gedoor/legado`, parses the release and offers the download when the
//  version is newer than the running one.
//

import Foundation

/// The information about a newer release.
public struct AppUpdateInfo: Equatable, Sendable {
    /// The version name, e.g. `3.4.9`.
    public let versionName: String
    /// The release note.
    public let note: String
    /// The download URL.
    public let downloadURL: String
    /// The release name.
    public let name: String

    public init(versionName: String, note: String, downloadURL: String, name: String) {
        self.versionName = versionName
        self.note = note
        self.downloadURL = downloadURL
        self.name = name
    }
}

/// The errors of the update check.
public enum AppUpdateError: Error, Equatable {
    /// The request failed.
    case requestFailed(Int)
    /// The response is not a release document.
    case invalidResponse
    /// The running version is the newest one.
    case alreadyLatest
}

/// The application update check.
public enum AppUpdateChecker {

    /// The GitHub API endpoint of the latest release — upstream
    /// `AppUpdateGitHub.getLatestRelease`.
    public static let releaseURL = "https://api.github.com/repos/gedoor/legado/releases/latest"

    /// The timeout of the upstream check (10 s).
    public static let timeout: TimeInterval = 10

    /// Asks GitHub for the latest release.
    public static func check(
        currentVersion: String,
        httpClient: HttpClient,
        userAgent: String = AppSettings.defaultUserAgent
    ) async throws -> AppUpdateInfo {
        let response = try await httpClient.send(
            HttpRequest(url: releaseURL, headers: ["User-Agent": userAgent])
        )
        guard response.isSuccessful else {
            throw AppUpdateError.requestFailed(response.code)
        }
        guard let body = response.body else {
            throw AppUpdateError.invalidResponse
        }
        return try parse(body, currentVersion: currentVersion)
    }

    /// Parses the release document of the GitHub API.
    ///
    /// The upstream compares the version names as STRINGS (`versionName >
    /// appInfo.versionName`); the port compares the numeric parts, so that
    /// `3.4.10` is newer than `3.4.9`.
    public static func parse(_ json: String, currentVersion: String) throws -> AppUpdateInfo {
        guard let value = try? JSONValue.parse(json) else {
            throw AppUpdateError.invalidResponse
        }
        let object = value.objectValue ?? [:]
        let tag = object["tag_name"]?.textValue ?? ""
        let name = object["name"]?.textValue ?? tag
        let note = object["body"]?.textValue ?? ""
        guard !tag.isEmpty else { throw AppUpdateError.invalidResponse }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: currentVersion) else {
            throw AppUpdateError.alreadyLatest
        }
        let downloadURL = Self.downloadURL(in: object) ?? releaseURL
        return AppUpdateInfo(
            versionName: version,
            note: note,
            downloadURL: downloadURL,
            name: name.isEmpty ? version : name
        )
    }

    /// The URL of the APK asset of the release (the upstream offers the
    /// `app-release.apk` asset).
    static func downloadURL(in object: [String: JSONValue]) -> String? {
        guard case let .array(assets)? = object["assets"] else { return nil }
        for asset in assets {
            guard let fields = asset.objectValue,
                  let name = fields["name"]?.textValue,
                  let url = fields["browser_download_url"]?.textValue else { continue }
            if name.hasSuffix(".apk") || name.hasSuffix(".ipa") {
                return url
            }
        }
        return assets.first?.objectValue?["browser_download_url"]?.textValue
    }

    /// Whether the candidate version is newer than the current one.
    ///
    /// The numeric parts are compared one by one; a version with more parts
    /// wins when the common parts are equal.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let right = current.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? numericPart(left[index]) : 0
            let r = index < right.count ? numericPart(right[index]) : 0
            if l != r { return l > r }
        }
        return false
    }

    /// The leading digits of a version part.
    private static func numericPart(_ text: String) -> Int {
        let digits = text.prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}
