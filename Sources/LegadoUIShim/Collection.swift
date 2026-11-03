//
//  Collection.swift
//  LegadoUIShim
//
//  The SwiftUI collection helpers that the shared view layer uses.
//
//  The real SwiftUI declares `move(fromOffsets:toOffset:)` in the
//  `RangeReplaceableCollection` extension; the shim mirrors it so that the
//  drag & drop of a list compiles on the platforms without SwiftUI.
//

import Foundation

extension Array {

    /// `SwiftUI.move(fromOffsets:toOffset:)` — moves the elements at the
    /// given offsets to the destination index.
    ///
    /// The semantics are the ones of the real SwiftUI: the destination index
    /// refers to the collection **before** the move, and the moved elements
    /// keep their relative order.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }
        let ordered = source.sorted()
        var moving: [Element] = []
        moving.reserveCapacity(ordered.count)
        for index in ordered {
            moving.append(self[index])
        }
        for index in ordered.reversed() {
            remove(at: index)
        }
        // The elements before the destination that were moved away shift the
        // insertion point to the left.
        let removedBefore = ordered.filter { $0 < destination }.count
        let insertion = Swift.max(0, Swift.min(destination - removedBefore, count))
        insert(contentsOf: moving, at: insertion)
    }
}
