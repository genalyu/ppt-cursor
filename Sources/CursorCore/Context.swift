import Foundation

public struct SlideTable: Codable, Equatable, Sendable {
    public let rows, columns: Int
    public let visibleSample: [[String?]]
}

/// All coordinates are in PowerPoint slide points, independent of zoom and display scale.
public struct SlideObject: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let name: String
    public let text: String?
    public let x, y, width, height, rotation: Double
    public var autoShapeType: String? = nil
    public var fillTransparency: Double? = nil
    public var solidFillRGB: [Int]? = nil
    public var table: SlideTable? = nil
    public var fontSize: Double? = nil
}

public struct TextSelection: Codable, Equatable, Sendable {
    public let offset, length: Int
}

public struct SlideSnapshot: Codable, Equatable, Sendable {
    public let document: String
    public let slideID: Int
    public let width, height: Double
    public let objects: [SlideObject]
    public var textSelection: TextSelection? = nil
    public var editingText: Bool? = nil
    public var viewZoom: Int? = nil
    public var selectedIDs: [String]? = nil
}

public struct EditContext: Encodable, Sendable {
    public let previous: [SlideSnapshot]
    public let current: SlideSnapshot
    public var imagesJustImported = false
    public var recentlyDismissed: [String] = []

    var acceptedTransitions: [String?] = []

    private struct Transition: Encodable {
        let before, after: [SlideObject]
        let selectionBefore, selectionAfter: [String]?
        let textSelectionBefore, textSelectionAfter: TextSelection?
        let previousOrder, nextOrder: [String]?
        let previousPageSize, nextPageSize: [Double]?

        let acceptedSuggestion: String?

        init(from old: SlideSnapshot, to new: SlideSnapshot, acceptedSuggestion: String?) {
            self.acceptedSuggestion = acceptedSuggestion
            let oldIndex = Dictionary(grouping: old.objects, by: \.id)
            let newIndex = Dictionary(grouping: new.objects, by: \.id)
            before = old.objects.filter { newIndex[$0.id]?.contains($0) != true }
            after = new.objects.filter { oldIndex[$0.id]?.contains($0) != true }
            selectionBefore = old.selectedIDs
            selectionAfter = new.selectedIDs
            textSelectionBefore = old.textSelection
            textSelectionAfter = new.textSelection
            let oldOrder = old.objects.map(\.id), newOrder = new.objects.map(\.id)
            previousOrder = oldOrder == newOrder ? nil : oldOrder
            nextOrder = oldOrder == newOrder ? nil : newOrder
            let resized = old.width != new.width || old.height != new.height
            previousPageSize = resized ? [old.width, old.height] : nil
            nextPageSize = resized ? [new.width, new.height] : nil
        }
    }

    private enum CodingKeys: String, CodingKey { case current, transitions, recentlyDismissed, imagesJustImported }

    private enum PageKeys: String, CodingKey { case width, height, objects, selectedIDs, textSelection }

    public func encode(to encoder: Encoder) throws {
        var output = encoder.container(keyedBy: CodingKeys.self)
        var page = output.nestedContainer(keyedBy: PageKeys.self, forKey: .current)
        try page.encode(current.width, forKey: .width)
        try page.encode(current.height, forKey: .height)
        try page.encode(current.objects, forKey: .objects)
        try page.encodeIfPresent(current.selectedIDs, forKey: .selectedIDs)
        try page.encodeIfPresent(current.textSelection, forKey: .textSelection)
        if imagesJustImported { try output.encode(true, forKey: .imagesJustImported) }
        if !recentlyDismissed.isEmpty { try output.encode(recentlyDismissed, forKey: .recentlyDismissed) }
        let states = previous + [current]
        let transitions = previous.indices.map { index in
            Transition(from: states[index], to: states[index + 1],
                       acceptedSuggestion: acceptedTransitions.indices.contains(index) ? acceptedTransitions[index] : nil)
        }
        try output.encode(transitions, forKey: .transitions)
    }
}

/// Geometry, content and stacking order are part of the baseline used to reject stale suggestions.
public struct EditHistory: Sendable {
    private var states: [SlideSnapshot] = []
    private var acceptedTransitions: [String?] = []
    private var dismissed: [(summary: String, remaining: Int)] = []
    private struct SavedPage: Sendable {
        let slideID: Int
        let acceptedTransitions: [String?]
        let states: [SlideSnapshot]
        let dismissed: [(summary: String, remaining: Int)]
    }
    private var recentPages: [SavedPage] = []
    private let limit: Int

    public init(limit: Int = 8) {
        self.limit = max(2, limit)
    }

    public var current: SlideSnapshot? { states.last }

    /// An explicit request, such as importing assets, can predict from a stationary slide.
    public var currentContext: EditContext? {
        guard let current else { return nil }
        return EditContext(previous: Array(states.dropLast()), current: current,
                           recentlyDismissed: dismissed.map(\.summary), acceptedTransitions: acceptedTransitions)
    }

    public mutating func reset() {
        recentPages.removeAll()
        states.removeAll()
        acceptedTransitions.removeAll()
        dismissed.removeAll()
    }

    public mutating func recordDismissal(_ summary: String, on baseline: SlideSnapshot) {
        guard baseline == current, !summary.isEmpty else { return }
        dismissed.removeAll { $0.summary == summary }
        dismissed.append((summary, limit - 1))
        if dismissed.count > limit { dismissed.removeFirst() }
    }

    /// Initial observation seeds history. Only a real change on the same slide starts prediction.
    public mutating func observe(_ state: SlideSnapshot, acceptedSuggestion: String? = nil) -> EditContext? {
        guard let last = current, last.document == state.document else {
            reset()
            states = [state]
            return nil
        }
        if last.slideID != state.slideID {
            let saved = recentPages.first { $0.slideID == state.slideID }
            recentPages.removeAll { $0.slideID == state.slideID }
            recentPages.append(SavedPage(slideID: last.slideID, acceptedTransitions: acceptedTransitions, states: states, dismissed: dismissed))
            if recentPages.count > 3 { recentPages.removeFirst() }
            if let saved, let page = saved.states.last, page.objects == state.objects,
               page.width == state.width, page.height == state.height {
                states = Array(saved.states.dropLast()) + [state]
                acceptedTransitions = saved.acceptedTransitions
                dismissed = saved.dismissed
            } else {
                states = [state]
                acceptedTransitions.removeAll()
                dismissed.removeAll()
            }
            return nil
        }
        guard last != state else { return nil }
        if last.objects == state.objects && last.width == state.width && last.height == state.height {
            // A focus change can invalidate a pending suggestion without constituting a new edit.
            states[states.count - 1] = state
            return nil
        }
        states.append(state)
        acceptedTransitions.append(acceptedSuggestion)
        if states.count > limit {
            states.removeFirst()
            acceptedTransitions.removeFirst()
        }
        let context = currentContext
        for index in dismissed.indices { dismissed[index].remaining -= 1 }
        dismissed.removeAll { $0.remaining == 0 }
        return context
    }
}
