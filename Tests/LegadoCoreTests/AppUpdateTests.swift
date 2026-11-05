//
//  AppUpdateTests.swift
//  LegadoCoreTests
//
//  The tests of the update check — the port of upstream
//  `help/update/AppUpdateGitHub.kt`.
//

import XCTest
@testable import LegadoCore

final class AppUpdateTests: XCTestCase {

    private let release = """
    {
      "tag_name": "v3.4.9",
      "name": "阅读 3.4.9",
      "body": "## 更新内容\\n- 修复了一些问题",
      "assets": [
        { "name": "app-release.apk", "browser_download_url": "https://example.com/app.apk" }
      ]
    }
    """

    // MARK: - The variant

    func testTheVariantValuesAreTheUpstreamOnes() {
        // Upstream `AppUpdateGitHub.checkVariant` knows "official_version",
        // "beta_release_version" and "beta_releaseA_version".
        XCTAssertEqual(AppVariant.official.rawValue, "official_version")
        XCTAssertEqual(AppVariant.betaRelease.rawValue, "beta_release_version")
        XCTAssertEqual(AppVariant.betaReleaseA.rawValue, "beta_releaseA_version")
        XCTAssertEqual(AppVariant.defaultVersion.rawValue, "default_version")
    }

    func testTheBetaVariantsUseTheBetaTag() {
        XCTAssertTrue(AppVariant.betaRelease.isBeta)
        XCTAssertTrue(AppVariant.betaReleaseA.isBeta)
        XCTAssertFalse(AppVariant.official.isBeta)
        XCTAssertFalse(AppVariant.defaultVersion.isBeta)
        XCTAssertEqual(
            AppUpdateChecker.releaseURL(variant: .betaRelease),
            "https://api.github.com/repos/gedoor/legado/releases/tags/beta"
        )
        XCTAssertEqual(
            AppUpdateChecker.releaseURL(variant: .official),
            "https://api.github.com/repos/gedoor/legado/releases/latest"
        )
    }

    func testThePreferenceSelectsTheVariant() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertEqual(settings.updateVariant, .defaultVersion)
        settings.updateVariant = .betaRelease
        XCTAssertEqual(settings.updateToVariant, "beta_release_version")
        XCTAssertEqual(settings.updateVariant, .betaRelease)
    }

    // MARK: - The check

    func testTheBetaVariantAsksTheBetaTag() async throws {
        let stub = StubHttpClient(handler: { _ in
            HttpResponse(url: "https://example.com", body: nil, code: 200, headers: [:])
        })
        _ = try? await AppUpdateChecker.check(
            currentVersion: "3.4.9",
            variant: .betaRelease,
            httpClient: stub
        )
        XCTAssertEqual(stub.requests.first?.url, AppUpdateChecker.betaReleaseURL)
    }

    func testTheOfficialVariantAsksTheLatestRelease() async throws {
        let stub = StubHttpClient(handler: { _ in
            HttpResponse(url: "https://example.com", body: nil, code: 200, headers: [:])
        })
        _ = try? await AppUpdateChecker.check(
            currentVersion: "3.4.9",
            variant: .official,
            httpClient: stub
        )
        XCTAssertEqual(stub.requests.first?.url, AppUpdateChecker.releaseURL)
    }

    func testTheReleaseIsParsed() throws {
        let info = try AppUpdateChecker.parse(release, currentVersion: "3.4.8")
        XCTAssertEqual(info.versionName, "3.4.9")
        XCTAssertEqual(info.name, "阅读 3.4.9")
        XCTAssertTrue(info.note.contains("修复了一些问题"))
        XCTAssertEqual(info.downloadURL, "https://example.com/app.apk")
    }

    func testARunningVersionThatIsTheNewestThrows() {
        XCTAssertThrowsError(try AppUpdateChecker.parse(release, currentVersion: "3.4.9")) { error in
            XCTAssertEqual(error as? AppUpdateError, .alreadyLatest)
        }
    }

    func testAFailedRequestIsReported() async throws {
        let stub = StubHttpClient(handler: { _ in
            HttpResponse(url: "https://example.com", body: nil, code: 404, headers: [:])
        })
        do {
            _ = try await AppUpdateChecker.check(currentVersion: "3.4.8", httpClient: stub)
            XCTFail("the check should fail")
        } catch {
            XCTAssertEqual(error as? AppUpdateError, .requestFailed(404))
        }
    }
}
