//
//  ShareViewController.swift
//  LegadoShareExtension
//
//  The share extension of the port — the iOS counterpart of
//  app/src/main/java/io/legado/app/receiver/SharedReceiverActivity.kt.
//
//  Upstream the Android app registers a receiver for `ACTION_SEND` and
//  `ACTION_PROCESS_TEXT` with the type `text/plain`. The shared text is
//  inspected: when it contains an address the app imports it, and everything
//  else is searched for.
//
//  The decision itself lives in `LegadoCore/App/SharedText.swift` so that it
//  can be unit-tested; this file only wires it into the extension.
//

import Foundation
import UIKit
import LegadoCore

/// The principal class of the share extension.
final class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedText()
    }

    /// Reads the shared text and opens the app for it.
    private func handleSharedText() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            finish()
            return
        }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] value, _ in
            let text: String
            if let string = value as? String {
                text = string
            } else if let url = value as? URL {
                text = url.absoluteString
            } else {
                text = ""
            }
            DispatchQueue.main.async {
                self?.open(text)
            }
        }
    }

    /// Opens the app with the deep link of the action.
    private func open(_ text: String) {
        let action = SharedText.action(for: text)
        guard let url = SharedText.deepLink(for: action) else {
            finish()
            return
        }
        extensionContext?.open(url, completionHandler: { [weak self] _ in
            self?.finish()
        })
    }

    /// Ends the extension.
    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
