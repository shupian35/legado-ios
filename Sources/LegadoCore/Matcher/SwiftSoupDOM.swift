import Foundation
import SwiftSoup

// MARK: - DOM bridging

/// Bridges `SwiftSoup.Element` into the port's DOM abstraction.
///
/// `SwiftSoup` is a direct port of `jsoup`, so the element semantics match
/// the Android app exactly: `text()` normalises whitespace, `ownText()` returns
/// only the direct text children, `data()` returns the combined data of the
/// child text nodes.
extension SwiftSoup.Element: DOMNode {

    public var nodeTag: String { tagName() }

    public var nodeText: String { (try? text()) ?? "" }

    public var nodeHTML: String { (try? outerHtml()) ?? "" }

    public var nodeAttributes: [String: String] {
        var result: [String: String] = [:]
        if let attributes = getAttributes() {
            for attribute in attributes {
                result[attribute.getKey()] = attribute.getValue()
            }
        }
        return result
    }

    public var nodeChildren: [any DOMNode] { Array(children()) }
}
