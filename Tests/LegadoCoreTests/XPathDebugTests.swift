import XCTest
@testable import LegadoCore

final class XPathDebugTests: XCTestCase {
    func testDumpTree() throws {
        let html = "<html><body><div id='c'><h1>Book Title</h1><p>First</p></div></body></html>"
        let document = try XPathDocument.parse(html)
        func dump(_ node: XPathNode, _ depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            print("\(indent)\(node.kind) name=\(node.name) value=\(node.value.prefix(20))")
            for child in node.children { dump(child, depth + 1) }
        }
        dump(document.root, 0)
        let nodes = try document.select("//h1/text()")
        print("SELECTED \(nodes.count)")
        let h1 = try document.select("//h1")
        print("H1 \(h1.count)")
    }
}
