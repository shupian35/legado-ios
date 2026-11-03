//
//  PdfKitDocument.swift
//  LegadoCore
//
//  The Apple-platform PDF renderer — the counterpart of Android's
//  `PdfRenderer` that upstream `model/localBook/PdfFile.kt` uses.
//
//  It is only compiled where PDFKit exists (iOS / macOS); on the other
//  platforms `RawPdfDocument` provides the page count and the port still
//  imports the book (the pages have no text or image).
//

#if canImport(PDFKit)

import Foundation
import PDFKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A PDF document backed by PDFKit.
public final class PdfKitDocument: PdfDocument {

    private let document: PDFDocument

    /// The number of pages.
    public var pageCount: Int { document.pageCount }

    /// Opens a PDF file.
    public init(url: URL) throws {
        guard let document = PDFDocument(url: url) else {
            throw PdfBookError.notAPdf
        }
        self.document = document
    }

    /// The text layer of a page.
    public func text(atPage index: Int) -> String? {
        guard index >= 0, index < document.pageCount else { return nil }
        return document.page(at: index)?.string
    }

    /// The rendered image of a page (PNG).
    public func imageData(atPage index: Int, scale: Double = 2) -> Data? {
        guard index >= 0, index < document.pageCount, let page = document.page(at: index) else {
            return nil
        }
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width > 0, size.height > 0 else { return nil }
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.pngData()
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}

#endif
