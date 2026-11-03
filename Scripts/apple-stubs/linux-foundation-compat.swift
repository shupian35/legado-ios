//
//  linux-foundation-compat.swift
//  Scripts/apple-stubs
//
//  The Linux-only companions of the Apple Foundation/UIKit API that
//  swift-corelibs-foundation does not have.
//
//  `Scripts/typecheck_apple.sh` compiles this file **into** the LegadoCore
//  module, so the Apple-only branches can be type-checked on Linux:
//
//    * `NSAttributedString.size()` is a UIKit/AppKit method;
//    * `NSAttributedString.Key.font` is a Darwin Foundation extension.
//
//  The file is never part of a real build — it lives outside `Sources/`.
//

#if os(Linux)
import Foundation

extension NSAttributedString.Key {

    /// Darwin Foundation: `NSFontAttributeName`.
    public static let font = NSAttributedString.Key("NSFont")
}

extension NSAttributedString {

    /// UIKit/AppKit: the size of the laid out string.
    ///
    /// The type check only needs the signature — the value is never used.
    public func size() -> CGSize {
        CGSize(width: Double(length) * 10, height: 20)
    }
}
#endif
