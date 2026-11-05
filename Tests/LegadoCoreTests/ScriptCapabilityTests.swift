//
//  ScriptCapabilityTests.swift
//  LegadoCoreTests
//
//  The capability model of the rule scripts.
//
//  The upstream Rhino engine guards the scripts with a class deny-list
//  (`modules/rhino/src/main/java/com/script/rhino/RhinoClassShutter.kt`):
//  everything that is not on the list stays reachable. The port replaces that
//  with an explicit allow-list, so a script only gets the capabilities its
//  environment grants.
//

import XCTest
@testable import LegadoCore

final class ScriptCapabilityTests: XCTestCase {

    // MARK: - The capability set

    func testTheDefaultSetGrantsWhatTheUpstreamScriptsUse() {
        let capabilities = ScriptCapabilities.default
        XCTAssertTrue(capabilities.contains(.network))
        XCTAssertTrue(capabilities.contains(.fileRead))
        XCTAssertTrue(capabilities.contains(.fileWrite))
        XCTAssertTrue(capabilities.contains(.cookies))
        XCTAssertTrue(capabilities.contains(.cache))
        XCTAssertTrue(capabilities.contains(.sourceData))
    }

    func testTheEmptySetGrantsNothing() {
        XCTAssertFalse(ScriptCapabilities.none.contains(.network))
        XCTAssertFalse(ScriptCapabilities.none.contains(.sourceData))
        XCTAssertTrue(ScriptCapabilities.none.isEmpty)
    }

    func testTheCapabilitiesAreIndependent() {
        var capabilities = ScriptCapabilities.none
        capabilities.insert(.network)
        XCTAssertTrue(capabilities.contains(.network))
        XCTAssertFalse(capabilities.contains(.fileRead))
        capabilities.insert(.fileRead)
        XCTAssertTrue(capabilities.contains(.network))
        XCTAssertTrue(capabilities.contains(.fileRead))
    }

    // MARK: - The guard

    func testTheGuardAcceptsAGrantedCapability() throws {
        let environment = ScriptEnvironment(capabilities: [.network])
        XCTAssertNoThrow(try environment.require(.network, name: "network"))
    }

    func testTheGuardRejectsACapabilityThatWasNotGranted() {
        let environment = ScriptEnvironment(capabilities: [.network])
        XCTAssertThrowsError(try environment.require(.fileWrite, name: "fileWrite")) { error in
            XCTAssertEqual(
                error as? ScriptEngineError,
                ScriptEngineError.capabilityDenied("fileWrite")
            )
        }
    }

    func testTheDefaultEnvironmentGrantsEverything() {
        let environment = ScriptEnvironment()
        XCTAssertEqual(environment.capabilities, .default)
    }

    // MARK: - The script engine

    func testTheUnavailableEngineReportsTheMissingPlatform() {
        let engine = UnavailableScriptEngine()
        XCTAssertThrowsError(try engine.evaluate("1 + 1", bindings: [:])) { error in
            guard case ScriptEngineError.unsupportedPlatform = error else {
                return XCTFail("expected an unsupportedPlatform error, got \(error)")
            }
        }
    }

    #if canImport(JavaScriptCore)
    // MARK: - The facade (Apple platforms only)

    func testTheScriptCannotUseTheNetworkWithoutTheCapability() {
        let environment = ScriptEnvironment(
            network: ScriptNetworkStub(),
            capabilities: [.fileRead]
        )
        let engine = JavaScriptCoreEngine(environment: environment)
        XCTAssertThrowsError(try engine.evaluate("java.ajax('https://example.com')", bindings: [:])) { error in
            guard case ScriptEngineError.scriptFailed = error else {
                return XCTFail("expected a script failure, got \(error)")
            }
        }
    }

    func testTheScriptCannotReadTheSourceDataWithoutTheCapability() {
        let environment = ScriptEnvironment(capabilities: [.network])
        let engine = JavaScriptCoreEngine(environment: environment)
        XCTAssertThrowsError(try engine.evaluate("java.put('a', 'b')", bindings: [:])) { error in
            guard case ScriptEngineError.scriptFailed = error else {
                return XCTFail("expected a script failure, got \(error)")
            }
        }
    }

    func testTheCookieBindingIsMissingWithoutTheCapability() {
        let environment = ScriptEnvironment(
            cookies: ScriptCookieStub(),
            capabilities: [.network]
        )
        let engine = JavaScriptCoreEngine(environment: environment)
        XCTAssertThrowsError(try engine.evaluate("cookie.get('https://example.com')", bindings: [:])) { error in
            guard case ScriptEngineError.scriptFailed = error else {
                return XCTFail("expected a script failure, got \(error)")
            }
        }
    }
    #endif
}

/// A network client for the capability tests.
private final class ScriptNetworkStub: ScriptNetworkClient {
    func scriptGet(_ url: String, headers: [String: String]) throws -> String { "ok" }
    func scriptPost(_ url: String, body: String?, headers: [String: String]) throws -> String { "ok" }
    func scriptDownload(_ url: String, headers: [String: String]) throws -> Data { Data("ok".utf8) }
}

/// A cookie store for the capability tests.
private final class ScriptCookieStub: ScriptCookieStore {
    func cookie(for url: String) -> String? { nil }
    func setCookie(_ value: String, for url: String) {}
}
