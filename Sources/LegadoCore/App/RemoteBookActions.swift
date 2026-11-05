//
//  RemoteBookActions.swift
//  LegadoCore
//
//  What happens when the user taps a book in the remote-book browser —
//  the port of `ui/book/import/remote/RemoteBookActivity.startRead` and
//  `addToBookShelfAgain`.
//
//  Upstream:
//
//  ```kotlin
//  override fun startRead(remoteBook: RemoteBook) {
//      val downloadFileName = remoteBook.filename
//      if (!ArchiveUtils.isArchive(downloadFileName)) {
//          appDb.bookDao.getBookByFileName(downloadFileName)?.let { startReadBook(it) }
//      } else {
//          AppConfig.defaultBookTreeUri ?: return
//          val downloadArchiveFileDoc = FileDoc.fromUri(…).find(downloadFileName)
//          if (downloadArchiveFileDoc == null) {
//              showRemoteBookDownloadAlert(remoteBook) { startRead(remoteBook) }
//          } else {
//              onArchiveFileClick(downloadArchiveFileDoc)
//          }
//      }
//  }
//  ```
//
//  The decision is kept here so that it can be tested; the download and the
//  import stay in the application layer.
//

import Foundation

/// What the remote-book browser does with a tapped book.
public enum RemoteBookAction: Equatable, Sendable {
    /// The book is already in the library — it is opened.
    case openBook(bookUrl: String)
    /// The archive is in the local storage — it is unpacked and the books
    /// inside it are opened.
    case openArchive(fileName: String)
    /// The archive is not in the local storage yet — it is downloaded first.
    /// The upstream shows the alert "压缩包没有找到" and downloads the book
    /// when the user confirms.
    case downloadArchive
    /// The book is not in the library and it is not an archive either — the
    /// upstream does nothing at all.
    case nothing
}

/// The actions of the remote-book browser.
public enum RemoteBookActions {

    /// Whether a remote file is an archive — upstream
    /// `ArchiveUtils.isArchive`.
    public static func isArchive(_ remote: RemoteBook) -> Bool {
        let ext = FileAssociation.fileExtension(of: remote.filename).lowercased()
        return FileAssociation.archiveExtensions.contains(ext)
    }

    /// What tapping a remote book does — upstream `startRead`.
    ///
    /// - Parameters:
    ///   - remote: the tapped book.
    ///   - bookOnShelf: the book of the library that has the same file name
    ///     (upstream `BookDao.getBookByFileName`).
    ///   - archiveExists: whether the archive is already in the local book
    ///     storage.
    public static func startRead(
        remote: RemoteBook,
        bookOnShelf: Book?,
        archiveExists: Bool
    ) -> RemoteBookAction {
        if !isArchive(remote) {
            guard let bookOnShelf else { return .nothing }
            return .openBook(bookUrl: bookOnShelf.bookUrl)
        }
        return archiveExists
            ? .openArchive(fileName: remote.filename)
            : .downloadArchive
    }

    /// The name of the local file of a remote book — the upstream looks the
    /// file up in the book storage folder (`AppConfig.defaultBookTreeUri`).
    public static func localFileName(_ remote: RemoteBook) -> String {
        remote.filename
    }
}
