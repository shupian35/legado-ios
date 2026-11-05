//
//  OpenURLRequest.swift
//  LegadoCore
//
//  The confirmation of an external link — the port of
//  app/src/main/java/io/legado/app/ui/association/OpenUrlConfirmActivity.kt
//  and OpenUrlConfirmDialog.kt.
//
//  Upstream a rule script that calls `java.openUrl(url, mimeType)` does not
//  open the link itself: it starts the confirmation activity, which asks the
//  user "「书源」正在请求跳转链接/应用，是否跳转？" and offers to disable or
//  delete the source that asked.
//

import Foundation

// MARK: - The request

/// The request of a script that wants to open an external link.
public struct OpenURLRequest: Equatable, Identifiable, Sendable {
    /// The address that is opened.
    public var url: String
    /// The type of the content — upstream the `mimeType` extra.
    public var mimeType: String?
    /// The key of the source that asked (upstream `sourceOrigin`).
    public var sourceKey: String?
    /// The name of the source that asked (upstream `sourceName`).
    public var sourceName: String

    public init(url: String, mimeType: String? = nil, sourceKey: String? = nil, sourceName: String = "") {
        self.url = url
        self.mimeType = mimeType
        self.sourceKey = sourceKey
        self.sourceName = sourceName
    }

    /// The identity of the request — the dialog is presented for it.
    public var id: String {
        "\(url)|\(mimeType ?? "")|\(sourceKey ?? "")"
    }

    /// The message of the dialog — upstream
    /// `"${viewModel.sourceName} 正在请求跳转链接/应用，是否跳转？"`.
    public var message: String {
        "\(sourceName) 正在请求跳转链接/应用，是否跳转？"
    }
}

// MARK: - The capability

/// The capability of the rule scripts — upstream `java.openUrl(url, mimeType)`.
public protocol ScriptOpenURLHandling: AnyObject {
    /// Asks the user whether the link may be opened.
    ///
    /// - Returns: `true` when the user accepted the request.
    func confirmOpenURL(url: String, mimeType: String?, sourceKey: String, sourceName: String) throws -> Bool
}

// MARK: - The coordinator

/// The coordinator of the open-url requests.
///
/// The upstream shows a dialog and parks the thread that called
/// `java.openUrl` until the user answers; the port does the same.
public final class OpenURLCoordinator: ScriptOpenURLHandling, @unchecked Sendable {

    /// How long a request waits for the user before it gives up.
    public static let defaultTimeout: TimeInterval = 180

    /// The request that is waiting for an answer.
    public private(set) var pending: OpenURLRequest?

    /// Called when a new request arrives — the user interface presents it.
    public var onRequest: ((OpenURLRequest) -> Void)?

    private let lock = NSLock()
    private var semaphore: DispatchSemaphore?
    private var accepted: Bool = false
    private var timeout: TimeInterval

    public init(timeout: TimeInterval = OpenURLCoordinator.defaultTimeout) {
        self.timeout = timeout
    }

    // MARK: - The requests

    public func confirmOpenURL(
        url: String,
        mimeType: String? = nil,
        sourceKey: String = "",
        sourceName: String = ""
    ) throws -> Bool {
        let request = OpenURLRequest(
            url: url,
            mimeType: mimeType,
            sourceKey: sourceKey.isEmpty ? nil : sourceKey,
            sourceName: sourceName
        )
        // Upstream `JsExtensions.openUrl`:
        // `require(url.length < 64 * 1024)`.
        guard request.url.count < 64 * 1024 else {
            throw ScriptEngineError.verificationFailed("跳转地址过长")
        }
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        // A second request cancels the first one.
        let previous = self.semaphore
        self.semaphore = semaphore
        self.accepted = false
        self.pending = request
        lock.unlock()
        previous?.signal()

        onRequest?(request)

        let waited = semaphore.wait(timeout: .now() + timeout)
        lock.lock()
        let value = accepted
        self.accepted = false
        self.pending = nil
        self.semaphore = nil
        lock.unlock()

        guard waited == .success else {
            throw ScriptEngineError.verificationFailed("跳转确认超时")
        }
        return value
    }

    // MARK: - The answers

    /// Delivers the answer of the user — the dialog is closed.
    public func complete(_ accepted: Bool) {
        lock.lock()
        self.accepted = accepted
        let semaphore = self.semaphore
        self.semaphore = nil
        lock.unlock()
        semaphore?.signal()
    }

    /// Aborts the request — the user closed the dialog without answering.
    public func cancel() {
        lock.lock()
        self.accepted = false
        let semaphore = self.semaphore
        self.semaphore = nil
        self.pending = nil
        lock.unlock()
        semaphore?.signal()
    }
}
