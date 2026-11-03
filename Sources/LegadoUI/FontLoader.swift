#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(CoreText)
import CoreText
#endif

/// The user font loader — upstream `ChapterProvider.getTypeface()` loads the
/// font file the user picked (`fontFolder`).
public enum FontLoader {

    /// Registers a font file with the system and returns the family name.
    ///
    /// Upstream falls back to the system typeface when the file cannot be
    /// loaded; the port does the same (the caller keeps the resolved
    /// descriptor).
    @discardableResult
    public static func register(fontPath: String) -> String? {
        #if canImport(CoreText)
        let url = URL(fileURLWithPath: fontPath) as CFURL
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url, .process, &error) else {
            // The font may already be registered — that is not an error.
            if let error = error?.takeRetainedValue() {
                let code = CFErrorGetCode(error)
                if code != 105 { return nil }
            } else {
                return nil
            }
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
        #else
        return nil
        #endif
    }

    /// The name of the font family of a file, without registering it.
    public static func familyName(fontPath: String) -> String? {
        #if canImport(CoreText)
        let url = URL(fileURLWithPath: fontPath) as CFURL
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
        #else
        return nil
        #endif
    }
}
