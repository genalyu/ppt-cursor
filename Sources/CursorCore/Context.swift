import Foundation

/// All coordinates are in PowerPoint slide points, independent of zoom and display scale.
public struct SlideObject: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let name: String
    public let text: String?
    public let x, y, width, height, rotation: Double
}

public struct SlideSnapshot: Codable, Equatable, Sendable {
    public let document: String
    public let slideID: Int
    public let width, height: Double
    public let objects: [SlideObject]
    public var selectedIDs: [String]? = nil
}

public struct EditContext: Encodable, Sendable {
    public let previous: [SlideSnapshot]
    public let current: SlideSnapshot
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
