import Foundation

/// `UniformTypeIdentifiers.UTType` — a stub for the Linux build.
///
/// On Apple platforms the real type comes from the `UniformTypeIdentifiers`
/// framework; the shim only needs the identifiers the UI refers to.
public struct UTType: Hashable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// `UTType(filenameExtension:)` — the shim maps the known extensions.
    public init?(filenameExtension: String) {
        let identifier: String
        switch filenameExtension.lowercased() {
        case "txt", "text": identifier = "public.plain-text"
        case "epub": identifier = "org.idpf.epub-container"
        case "pdf": identifier = "com.adobe.pdf"
        case "umd": identifier = "public.data"
        case "ttf", "otf": identifier = "public.font"
        default: identifier = "public.data"
        }
        self.identifier = identifier
    }

    /// The font types — upstream `FontSelectDialog` accepts the font files.
    ///
    /// The real `UTType` has exactly one font member (`font`, `public.font`);
    /// the shim must not invent the others, or Linux would accept code that
    /// does not compile on Apple platforms.
    public static let font = UTType(identifier: "public.font")
    public static let data = UTType(identifier: "public.data")

    /// `UTType.folder` — the folder picker (the scan of a folder for the books).
    public static let folder = UTType(identifier: "public.folder")

    /// `UTType.zip` — the archive of the reader style (`readConfig.zip`).
    public static let zip = UTType(identifier: "public.zip-archive")
}
