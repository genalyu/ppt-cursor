import Foundation

/// All coordinates are in PowerPoint slide points, independent of zoom and display scale.
public struct SlideObject: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let name: String
    public let text: String?
    public let x, y, width, height, rotation: Double
    public var fontSize: Double? = nil
}

public struct SlideSnapshot: Codable, Equatable, Sendable {
    public let document: String
    public let slideID: Int
    public let width, height: Double
    public let objects: [SlideObject]
    public var viewZoom: Int? = nil
    public var selectedIDs: [String]? = nil
}

public struct EditContext: Encodable, Sendable {
    public let previous: [SlideSnapshot]
    public let current: SlideSnapshot

    private struct Transition: Encodable {
        let before, after: [SlideObject]
        let selectionBefore, selectionAfter: [String]?
        let previousOrder, nextOrder: [String]?
        let previousPageSize, nextPageSize: [Double]?

        init(from old: SlideSnapshot, to new: SlideSnapshot) {
            let oldIndex = Dictionary(grouping: old.objects, by: \.id)
            let newIndex = Dictionary(grouping: new.objects, by: \.id)
            before = old.objects.filter { newIndex[$0.id]?.contains($0) != true }
            after = new.objects.filter { oldIndex[$0.id]?.contains($0) != true }
            selectionBefore = old.selectedIDs
            selectionAfter = new.selectedIDs
            let oldOrder = old.objects.map(\.id), newOrder = new.objects.map(\.id)
            previousOrder = oldOrder == newOrder ? nil : oldOrder
            nextOrder = oldOrder == newOrder ? nil : newOrder
            let resized = old.width != new.width || old.height != new.height
            previousPageSize = resized ? [old.width, old.height] : nil
            nextPageSize = resized ? [new.width, new.height] : nil
        }
    }

    private enum CodingKeys: String, CodingKey { case current, transitions }

    private enum PageKeys: String, CodingKey { case width, height, objects, selectedIDs }

    public func encode(to encoder: Encoder) throws {
        var output = encoder.container(keyedBy: CodingKeys.self)
        var page = output.nestedContainer(keyedBy: PageKeys.self, forKey: .current)
        try page.encode(current.width, forKey: .width)
        try page.encode(current.height, forKey: .height)
        try page.encode(current.objects, forKey: .objects)
        try page.encodeIfPresent(current.selectedIDs, forKey: .selectedIDs)
        let states = previous + [current]
        let transitions = zip(states, states.dropFirst()).map { Transition(from: $0, to: $1) }
        try output.encode(transitions, forKey: .transitions)
    }
}

/// Geometry, content and stacking order are part of the baseline used to reject stale suggestions.
public struct EditHistory: Sendable {
    private var states: [SlideSnapshot] = []
    private let limit: Int

    public init(limit: Int = 8) {
        self.limit = max(2, limit)
    }

    public var current: SlideSnapshot? { states.last }

    public mutating func reset() { states.removeAll() }

    /// Initial observation seeds history. Only a real change on the same slide starts prediction.
    public mutating func observe(_ state: SlideSnapshot) -> EditContext? {
        guard let last = current, last.document == state.document, last.slideID == state.slideID else {
            states = [state]
            return nil
        }
        guard last != state else { return nil }
        if last.objects == state.objects && last.width == state.width && last.height == state.height {
            // A focus change can invalidate a pending suggestion without constituting a new edit.
            states[states.count - 1] = state
            return nil
        }
        states.append(state)
        if states.count > limit { states.removeFirst(states.count - limit) }
        return EditContext(previous: Array(states.dropLast()), current: state)
    }
}
