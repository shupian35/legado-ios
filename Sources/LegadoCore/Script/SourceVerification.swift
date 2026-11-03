//
//  SourceVerification.swift
//  LegadoCore
//
//  The source verification — the image captcha and the anti-scraping page
//  that a book source asks the user to solve.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/source/SourceVerificationHelp.kt
//  app/src/main/java/io/legado/app/ui/association/VerificationCodeDialog.kt
//  app/src/main/java/io/legado/app/ui/association/VerificationCodeActivity.kt
//  app/src/main/java/io/legado/app/help/JsExtensions.kt (getVerificationCode)
//

import Foundation

/// The kind of verification the user has to solve.
public enum SourceVerificationKind: String, Sendable {
    /// The image captcha — upstream `VerificationCodeActivity`.
    case captcha
    /// The anti-scraping page in the built-in browser — upstream
    /// `WebViewActivity` with `sourceVerificationEnable`.
    case browser
}

/// A verification request that waits for the user.
///
/// The upstream stores the request in the intent data, starts the
/// verification activity and parks the calling thread until the activity is
/// destroyed; the port keeps the same shape: the request is handed to the
/// user interface and the calling thread waits for the answer.
public struct SourceVerificationRequest: Identifiable, Sendable, Equatable {

    public let id: UUID
    public let kind: SourceVerificationKind
    /// The address of the captcha image (the `captcha` kind).
    public let imageURL: String?
    /// The address of the page (the `browser` kind).
    public let url: String
    /// The key of the source that asked for the verification.
    public let sourceKey: String
    /// The name of the source, shown as the subtitle of the dialog.
    public let sourceName: String

    public init(
        id: UUID = UUID(),
        kind: SourceVerificationKind,
        imageURL: String? = nil,
        url: String = "",
        sourceKey: String,
        sourceName: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.imageURL = imageURL
        self.url = url
        self.sourceKey = sourceKey
        self.sourceName = sourceName
    }
}

/// The verification capability of the rule scripts.
public protocol ScriptVerificationHandling: AnyObject {
    /// Upstream `java.getVerificationCode(imageUrl)` — shows the captcha and
    /// waits for the user to type the code.
    func verificationCode(imageURL: String, sourceKey: String, sourceName: String) throws -> String
    /// Upstream `java.startBrowserAwait(url, title)` — shows the page in the
    /// built-in browser and waits for the user to finish the check.
    func browserResult(url: String, sourceKey: String, sourceName: String) throws -> String
}

/// The coordinator of the verification requests.
///
/// Upstream `SourceVerificationHelp` keeps the result of the verification in
/// the memory cache under `"<sourceKey>_verificationResult"` and parks the
/// thread that asked for it. The port does the same: the coordinator publishes
/// the request to the user interface and waits on a semaphore until the
/// interface answers.
public final class SourceVerificationCoordinator: ScriptVerificationHandling, @unchecked Sendable {

    /// How long a request waits for the user before it gives up.
    ///
    /// The upstream waits forever (`LockSupport.parkNanos` in a loop); the port
    /// gives up after three minutes so a forgotten dialog cannot block a rule
    /// evaluation forever.
    public static let defaultTimeout: TimeInterval = 180

    /// The request that is waiting for an answer.
    public private(set) var pending: SourceVerificationRequest?

    /// Called when a new request arrives — the user interface presents it.
    public var onRequest: ((SourceVerificationRequest) -> Void)?

    private let lock = NSLock()
    private var semaphore: DispatchSemaphore?
    private var result: String?
    private var timeout: TimeInterval

    public init(timeout: TimeInterval = SourceVerificationCoordinator.defaultTimeout) {
        self.timeout = timeout
    }

    // MARK: - The requests

    public func verificationCode(
        imageURL: String,
        sourceKey: String,
        sourceName: String = ""
    ) throws -> String {
        try await_(
            SourceVerificationRequest(
                kind: .captcha,
                imageURL: imageURL,
                url: imageURL,
                sourceKey: sourceKey,
                sourceName: sourceName
            )
        )
    }

    public func browserResult(
        url: String,
        sourceKey: String,
        sourceName: String = ""
    ) throws -> String {
        try await_(
            SourceVerificationRequest(
                kind: .browser,
                imageURL: nil,
                url: url,
                sourceKey: sourceKey,
                sourceName: sourceName
            )
        )
    }

    /// Publishes the request and waits for the answer.
    private func await_(_ request: SourceVerificationRequest) throws -> String {
        // Upstream `SourceVerificationHelp.getVerificationResult`:
        // `require(url.length < 64 * 1024)` and
        // `check(!isMainThread) { "getVerificationResult must be called on a
        // background thread" }`.
        guard request.url.count < 64 * 1024 else {
            throw ScriptEngineError.verificationFailed("验证地址过长")
        }
        guard !Thread.isMainThread else {
            throw ScriptEngineError.verificationFailed("验证必须在后台线程调用")
        }
        let semaphore = DispatchSemaphore(value: 0)
        lock.lock()
        // A second request cancels the first one — the upstream clears the
        // result of the source before it starts a new verification.
        let previous = self.semaphore
        self.semaphore = semaphore
        self.result = nil
        self.pending = request
        lock.unlock()
        previous?.signal()

        onRequest?(request)

        let waited = semaphore.wait(timeout: .now() + timeout)
        lock.lock()
        let value = result
        self.result = nil
        self.pending = nil
        self.semaphore = nil
        lock.unlock()

        guard waited == .success else {
            throw ScriptEngineError.verificationFailed("验证超时")
        }
        guard let value, !value.isEmpty else {
            // Upstream `NoStackTraceException("验证结果为空")`.
            throw ScriptEngineError.verificationFailed("验证结果为空")
        }
        return value
    }

    // MARK: - The answers

    /// Delivers the answer of the user — upstream `SourceVerificationHelp.setResult`.
    public func complete(_ value: String) {
        lock.lock()
        result = value
        let semaphore = self.semaphore
        self.semaphore = nil
        lock.unlock()
        semaphore?.signal()
    }

    /// Aborts the request — the user closed the dialog.
    public func cancel() {
        lock.lock()
        result = nil
        let semaphore = self.semaphore
        self.semaphore = nil
        self.pending = nil
        lock.unlock()
        semaphore?.signal()
    }
}
