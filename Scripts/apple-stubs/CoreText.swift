//
//  CoreText.swift
//  apple-stubs
//
//  A **type-check only** stand-in for CoreText.
//
//  See `UIKit.swift` in this folder for the rationale. Only the declarations
//  the port uses are here and every signature mirrors the real Apple API.
//
//  CoreFoundation does not exist on Linux, so the stub declares the few
//  CoreFoundation types the port needs (`CFURL`, `CFString`, `CFArray`,
//  `CFError`).
//

import Foundation

// MARK: - The CoreFoundation types

public typealias CFURL = URL
public typealias CFString = NSString
public typealias CFArray = NSArray

/// `CoreFoundation.CFError`.
public class CFError: NSObject {}

/// `CoreFoundation.CFErrorGetCode`.
public func CFErrorGetCode(_ error: CFError) -> Int { 0 }

// MARK: - The font manager

/// `CoreText.CTFontManagerScope`.
public struct CTFontManagerScope: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let none = CTFontManagerScope([])
    public static let process = CTFontManagerScope(rawValue: 1)
    public static let user = CTFontManagerScope(rawValue: 2)
    public static let session = CTFontManagerScope(rawValue: 3)
}

/// `CoreText.CTFontDescriptor`.
open class CTFontDescriptor: NSObject {
    open var url: URL?
    public override init() { super.init() }
}

/// `CoreText.CTFont`.
open class CTFont: NSObject {
    open var familyName: String { "" }
    open var pointSize: CGFloat { 0 }
    open var ascent: CGFloat { 0 }
    open var descent: CGFloat { 0 }
    open var leading: CGFloat { 0 }
    open var capHeight: CGFloat { 0 }
    open var xHeight: CGFloat { 0 }
    open var italicAngle: CGFloat { 0 }
    open var underlinePosition: CGFloat { 0 }
    open var underlineThickness: CGFloat { 0 }
    open var strikethroughPosition: CGFloat { 0 }
    open var strikethroughThickness: CGFloat { 0 }
    open var path: URL? { nil }
}

/// The font family name attribute.
public let kCTFontFamilyNameAttribute: CFString = "NSFontFamilyAttribute" as CFString

/// `CoreText.CTFontManagerRegisterFontsForURL`.
public func CTFontManagerRegisterFontsForURL(
    _ fontURL: CFURL,
    _ scope: CTFontManagerScope,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> Bool { true }

/// `CoreText.CTFontManagerUnregisterFontsForURL`.
public func CTFontManagerUnregisterFontsForURL(
    _ fontURL: CFURL,
    _ scope: CTFontManagerScope,
    _ error: UnsafeMutablePointer<Unmanaged<CFError>?>?
) -> Bool { true }

/// `CoreText.CTFontManagerCreateFontDescriptorsFromURL`.
public func CTFontManagerCreateFontDescriptorsFromURL(_ fileURL: CFURL) -> CFArray? { nil }

/// `CoreText.CTFontManagerCreateFontDescriptorFromURL`.
public func CTFontManagerCreateFontDescriptorFromURL(_ fileURL: CFURL) -> CTFontDescriptor? { nil }

/// `CoreText.CTFontDescriptorCopyAttribute`.
public func CTFontDescriptorCopyAttribute(
    _ descriptor: CTFontDescriptor,
    _ attribute: CFString
) -> AnyObject? { nil }
