//
//  PDFKit.swift
//  apple-stubs
//
//  A **type-check only** stand-in for PDFKit.
//
//  See `UIKit.swift` in this folder for the rationale. Only the declarations
//  the port uses are here and every signature mirrors the real Apple API.
//

import Foundation
import UIKit

/// `PDFKit.PDFBox`.
public enum PDFBox: Int {
    case mediaBox = 0
    case cropBox = 1
    case bleedBox = 2
    case trimBox = 3
    case artBox = 4
}

/// `PDFKit.PDFDisplayBox`.
public enum PDFDisplayBox: Int {
    case mediaBox = 0
    case cropBox = 1
    case bleedBox = 2
    case trimBox = 3
    case artBox = 4
}

/// `PDFKit.PDFPage`.
open class PDFPage: NSObject {
    open var string: String? { nil }
    open var bounds: CGRect { .zero }
    open func bounds(for box: PDFBox) -> CGRect { .zero }
    open func draw(with box: PDFDisplayBox, to context: CGContext) {}
}

/// `PDFKit.PDFDocument`.
open class PDFDocument: NSObject {
    open var pageCount: Int { 0 }
    open var isLocked: Bool { false }
    open var string: String? { nil }

    public convenience init?(url: URL) { self.init() }
    public convenience init?(data: Data) { self.init() }
    public override init() { super.init() }

    open func page(at index: Int) -> PDFPage? { nil }
    open func index(for page: PDFPage) -> Int { 0 }
}
