import Foundation
import SwiftSoup

/// Faithful port of the `AnalyzeByJSoup.ElementsSingle` data class.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt:282-511
///
/// Two index syntaxes are supported:
///
/// 1. the legacy syntax uses `:` to separate indexes and `!` or `.` to pick the
///    filtering mode; indexes may be negative — e.g. `tag.div.-1:10:2`,
///    `tag.div!0:3`;
/// 2. a JSONPath-like `[]` syntax — `[it,it,…]` or `[!it,it,…]` where a leading
///    `!` means "exclude" and `it` is an index or a range. A range is
///    `start:end` or `start:end:step`; the start may be omitted (0) and the end
///    may be omitted (-1). Indexes, both ends and the step may be negative —
///    e.g. `tag.div[-1, 3:-2:-10, 2]`. The special form `tag.div[-1:0]`
///    reverses the list.
public struct ElementsSingle {

    /// The filtering mode: `!` = exclude, `.` = select, ` ` = no filtering.
    private(set) var split: Character = "."
    /// The rule without the index part.
    private(set) var beforeRule: String = ""
    /// The indexes of the legacy syntax.
    private var indexDefault: [Int] = []
    /// The indexes of the bracket syntax.
    private var indexes: [IndexSpec] = []

    /// One entry of the bracket syntax.
    private enum IndexSpec {
        /// A single index.
        case single(Int)
        /// A range; `nil` means "omitted" (0 for the start, `len - 1` for the end).
        case range(start: Int?, end: Int?, step: Int)
    }

    public init() {}

    /// Port of `ElementsSingle.getElementsSingle`.
    public func getElementsSingle(_ temp: Element, _ rule: String) throws -> [Element] {
        var state = ElementsSingle()
        try state.findIndexSet(rule)

        var elements: [Element]
        if state.beforeRule.isEmpty {
            elements = Array(temp.children())
        } else {
            // Kotlin's `split(".")` keeps empty segments.
            let rules = state.beforeRule
                .split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            guard let first = rules.first else { return [] }
            switch first {
            case "children":
                elements = Array(temp.children())
            case "class":
                elements = Array(try temp.getElementsByClass(try state.argument(rules, 1, rule)))
            case "tag":
                elements = Array(try temp.getElementsByTag(try state.argument(rules, 1, rule)))
            case "id":
                if let found = try temp.getElementById(try state.argument(rules, 1, rule)) {
                    elements = [found]
                } else {
                    elements = []
                }
            case "text":
                elements = Array(try temp.getElementsContainingOwnText(try state.argument(rules, 1, rule)))
            default:
                elements = Array(try temp.select(state.beforeRule))
            }
        }
        return try state.filter(elements)
    }

    // MARK: - Helpers

    /// Read the `index`-th segment of a split rule, throwing when it is absent.
    private func argument(_ rules: [String], _ index: Int, _ rule: String) throws -> String {
        guard index < rules.count else {
            throw ElementsSingleError.missingSegment(rule)
        }
        return rules[index]
    }

    /// Apply the index selection to the candidate elements.
    private func filter(_ elements: [Element]) throws -> [Element] {
        let len = elements.count
        let lastIndexes = indexDefault.isEmpty ? indexes.count - 1 : indexDefault.count - 1

        // Kotlin uses a LinkedHashSet, so the insertion order is preserved.
        var indexSet: [Int] = []
        var seen: Set<Int> = []
        func add(_ value: Int) {
            guard !seen.contains(value) else { return }
            seen.insert(value)
            indexSet.append(value)
        }

        if indexes.isEmpty {
            // Legacy syntax. The list was collected right-to-left, so it is
            // traversed backwards to restore the original order.
            if lastIndexes >= 0 {
                for ix in stride(from: lastIndexes, through: 0, by: -1) {
                    let it = indexDefault[ix]
                    if it >= 0 && it < len {
                        add(it)
                    } else if it < 0 && len >= -it {
                        add(it + len)
                    }
                }
            }
        } else {
            if lastIndexes >= 0 {
                for ix in stride(from: lastIndexes, through: 0, by: -1) {
                    switch indexes[ix] {
                    case .single(let it):
                        if it >= 0 && it < len {
                            add(it)
                        } else if it < 0 && len >= -it {
                            add(it + len)
                        }
                    case .range(let startX, let endX, let stepX):
                        var start = startX ?? 0
                        if start < 0 { start += len }

                        var end = endX ?? (len - 1)
                        if end < 0 { end += len }

                        if (start < 0 && end < 0) || (start >= len && end >= len) {
                            // Both ends are out of bounds on the same side.
                            continue
                        }

                        if start >= len {
                            start = len - 1
                        } else if start < 0 {
                            start = 0
                        }

                        if end >= len {
                            end = len - 1
                        } else if end < 0 {
                            end = 0
                        }

                        if start == end || stepX >= len {
                            add(start)
                            continue
                        }

                        // The smallest positive step is 1.
                        let step = stepX > 0 ? stepX : (-stepX < len ? stepX + len : 1)

                        if end > start {
                            var index = start
                            while index <= end {
                                add(index)
                                index += step
                            }
                        } else {
                            var index = start
                            while index >= end {
                                add(index)
                                index -= step
                            }
                        }
                    }
                }
            }
        }

        if split == "!" {
            // Exclude the indexed elements.
            let removed = Set(indexSet)
            return elements.enumerated()
                .filter { !removed.contains($0.offset) }
                .map(\.element)
        }
        if split == "." {
            // Keep only the indexed elements.
            var selected: [Element] = []
            for position in indexSet where position < elements.count {
                selected.append(elements[position])
            }
            return selected
        }
        return elements
    }

    // MARK: - Rule parsing

    /// Port of `ElementsSingle.findIndexSet`.
    ///
    /// The rule is scanned **backwards**: the index part always sits at the end
    /// of the rule, so scanning from the right finds it first.
    private mutating func findIndexSet(_ rule: String) throws {
        let rus = rule.trimmingJavaSpaces()
        let characters = Array(rus)

        var len = characters.count
        var curInt: Int?
        var curMinus = false
        var curList: [Int?] = []
        var l = ""

        let head = characters.last == "]"

        if head {
            // The regular `[index…]` syntax — skip the trailing `]`.
            len -= 1
            scan: while true {
                let keepGoing = len >= 0
                len -= 1
                if !keepGoing { break scan }
                guard len >= 0, len < characters.count else { break scan }

                var rl = characters[len]
                if rl == " " { continue scan }

                if (rl >= "0" && rl <= "9") {
                    l = String(rl) + l
                } else if rl == "-" {
                    curMinus = true
                } else {
                    if l.isEmpty {
                        curInt = nil
                    } else if curMinus {
                        guard let value = Int(l) else { throw ElementsSingleError.invalidNumber(l) }
                        curInt = -value
                    } else {
                        guard let value = Int(l) else { throw ElementsSingleError.invalidNumber(l) }
                        curInt = value
                    }

                    if rl == ":" {
                        // The right end of a range, or its step.
                        curList.append(curInt)
                    } else {
                        if curList.isEmpty {
                            guard let value = curInt else {
                                // Not an index list but a plain selector.
                                break scan
                            }
                            indexes.append(.single(value))
                        } else {
                            // The last pushed value is the right end of the range;
                            // when two values were pushed the first one is the step.
                            let rightEnd = curList[curList.count - 1]
                            let step = curList.count == 2 ? (curList[0] ?? 1) : 1
                            indexes.append(.range(start: curInt, end: rightEnd, step: step))
                            curList.removeAll()
                        }

                        if rl == "!" {
                            split = "!"
                            repeat {
                                len -= 1
                                guard len >= 0, len < characters.count else { break }
                                rl = characters[len]
                            } while len > 0 && rl == " "
                        }

                        if rl == "[" {
                            beforeRule = String(characters[0..<len])
                            return
                        }

                        if rl != "," { break scan }
                    }

                    l = ""
                    curMinus = false
                }
            }
        } else {
            // The legacy syntax — `tag.div.-1:10:2` / `tag.div!0:3`.
            scan: while true {
                let keepGoing = len >= 0
                len -= 1
                if !keepGoing { break scan }
                guard len >= 0, len < characters.count else { break scan }

                let rl = characters[len]
                if rl == " " { continue scan }

                if (rl >= "0" && rl <= "9") {
                    l = String(rl) + l
                } else if rl == "-" {
                    curMinus = true
                } else {
                    if rl == "!" || rl == "." || rl == ":" {
                        guard let value = Int(l) else { throw ElementsSingleError.invalidNumber(l) }
                        indexDefault.append(curMinus ? -value : value)

                        if rl != ":" {
                            split = rl
                            beforeRule = String(characters[0..<len])
                            return
                        }
                    } else {
                        break scan
                    }
                    l = ""
                    curMinus = false
                }
            }
        }

        split = " "
        beforeRule = rus
    }
}

/// Errors raised while parsing an index rule.
public enum ElementsSingleError: Error, Equatable {
    /// The rule ends with a separator but no number.
    case invalidNumber(String)
    /// A `class.` / `tag.` / `id.` / `text.` prefix without its argument.
    case missingSegment(String)
}
