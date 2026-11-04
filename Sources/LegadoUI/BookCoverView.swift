//
//  BookCoverView.swift
//  LegadoUI
//
//  The cover of a book — upstream `ui/book/info/CoverImageView` and the
//  `ItemBookshelfGrid`/`ItemBookshelfList` covers.
//
//  The cover URL of a book is the custom cover first, then the cover of the
//  source (upstream `Book.getCustomCoverUrl` / `Book.getRealCoverUrl`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The cover image of a book.
public struct BookCoverView: View {

    let book: Book
    /// The width of the cover.
    var width: Double = 56
    /// The height of the cover.
    var height: Double = 76

    public var body: some View {
        Group {
            if let url = coverURL, let remote = URL(string: url) {
                AsyncImage(url: remote) { phase in
                    if case let .success(image) = phase {
                        return AnyView(image.resizable().aspectRatio(contentMode: .fill))
                    }
                    return AnyView(placeholder)
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .cornerRadius(4)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
            Text(String(book.name.prefix(1)))
                .font(.system(size: max(12, width / 3)))
                .foregroundColor(.secondary)
        }
    }

    /// The URL of the cover — upstream `Book.getCoverUrl`.
    private var coverURL: String? {
        if let custom = book.customCoverUrl, !custom.isEmpty {
            // The upstream's marker of the generated default cover — the
            // cover is drawn by the placeholder.
            if custom == legadoDefaultCoverMarker { return nil }
            return custom
        }
        if let cover = book.coverUrl, !cover.isEmpty {
            return cover
        }
        return nil
    }
}

/// The group picker — upstream `BookGroupDialog` / `GroupSelectDialog`.
struct GroupPickerSheet: View {

    @Environment(\.dismiss) private var dismiss

    let groups: [BookGroup]
    /// The bit mask of the groups the book is in.
    let selected: Int64
    /// Whether the user may select several groups.
    let allowsMultiple: Bool
    let onSelect: (Int64) -> Void

    init(
        groups: [BookGroup],
        selected: Int64 = 0,
        allowsMultiple: Bool = true,
        onSelect: @escaping (Int64) -> Void
    ) {
        self.groups = groups
        self.selected = selected
        self.allowsMultiple = allowsMultiple
        self.onSelect = onSelect
    }

    var body: some View {
        List {
            ForEach(groups, id: \.groupId) { group in
                Button {
                    onSelect(group.groupId)
                    dismiss()
                } label: {
                    HStack {
                        Text(group.groupName)
                            .font(.system(size: 14))
                        Spacer()
                        if isSelected(group) {
                            Text("已选")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .navigationTitle("分组")
    }

    /// Whether the group is in the bit mask — upstream `BookAdapter.getGroupList`
    /// (`it.groupId > 0 && (it.groupId and groupId) > 0`).
    private func isSelected(_ group: BookGroup) -> Bool {
        group.groupId > 0 && (group.groupId & selected) > 0
    }
}

/// The helper that computes the group names of a book.
///
/// Upstream `BookAdapter.getGroupList` / `BookInfoViewModel.getGroupName`.
enum BookGroups {

    /// The names of the groups a book belongs to.
    static func names(for book: Book, groups: [BookGroup]) -> [String] {
        groups
            .filter { $0.groupId > 0 && ($0.groupId & book.group) > 0 }
            .map(\.groupName)
    }

    /// The bit mask of the selected groups — upstream `Book.group` is the OR
    /// of the group ids.
    static func mask(for groupIds: [Int64]) -> Int64 {
        groupIds.reduce(0) { $0 | $1 }
    }

    /// Toggles a group in a bit mask.
    static func toggling(_ groupId: Int64, in mask: Int64) -> Int64 {
        guard groupId > 0 else { return mask }
        if (groupId & mask) > 0 {
            return mask & ~groupId
        }
        return mask | groupId
    }
}
