//
//  ScriptEngineFactory.swift
//  LegadoCore
//
//  Builds the JavaScript runtime the rule scripts run in.
//
//  The upstream runs the scripts in Rhino, which is part of the app on every
//  platform. On iOS the equivalent engine is JavaScriptCore, which only
//  exists on Apple platforms, so the factory returns `nil` elsewhere and the
//  rules that need JavaScript report the missing capability.
//
//  Upstream reference:
//  modules/rhino (the Rhino engine)
//  app/src/main/java/io/legado/app/help/JsExtensions.kt (the `java` facade)
//

import Foundation

/// Creates the script engine of the application.
public enum ScriptEngineFactory {

    /// The engine the rule scripts run in.
    ///
    /// - Parameters:
    ///   - login: the login service; it is handed to the engine so that
    ///     `java.putLoginHeader` reaches the store.
    ///   - cookieStore: the cookie jar of the app.
    ///   - httpClient: the transport the `java.ajax` calls use.
    ///   - userAgent: the user agent of the requests the scripts make.
    ///   - sandboxDirectory: the directory the file calls are confined to
    ///     (upstream the cache directory of the app).
    ///   - verification: the coordinator of the source verification — the
    ///     captcha dialog the user has to solve.
    /// - Returns: the engine, or `nil` when the platform has no JavaScript
    ///   engine (the Linux CI build).
    public static func make(
        login: SourceLoginService,
        cookieStore: CookieStore,
        httpClient: HttpClient,
        userAgent: String = AppSettings.defaultUserAgent,
        sandboxDirectory: String,
        verification: ScriptVerificationHandling? = nil
    ) -> RuleScriptEngine? {
        #if canImport(JavaScriptCore)
        let environment = ScriptEnvironment(
            network: HttpScriptClient(
                httpClient: httpClient,
                cookieStore: cookieStore,
                userAgent: userAgent
            ),
            files: SandboxFileSandbox(baseDirectory: sandboxDirectory),
            cookies: CookieScriptStore(cookieStore: cookieStore),
            cache: MemoryScriptCache(),
            login: login,
            verification: verification,
            defaultHeaders: userAgent.isEmpty ? [:] : ["User-Agent": userAgent],
            capabilities: .default
        )
        let engine = JavaScriptCoreEngine(environment: environment)
        // The login scripts need the engine as well.
        login.scriptEngine = engine
        return engine
        #else
        return nil
        #endif
    }
}
