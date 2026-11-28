import Foundation

/// Ignore observations crossing a write and require a stable document switch.
/// PowerPoint briefly activates a staging deck while copying native shapes.
struct DocumentFollowPolicy {
    private(set) var generation = 0
    private var candidate: URL?
    private var firstSeen = Date.distantPast

    mutating func invalidate() {
        generation += 1
        candidate = nil
        firstSeen = .distantPast
    }

    mutating func shouldFollow(_ observed: URL, active: URL, generation observedGeneration: Int,
                               applying: Bool, now: Date = Date()) -> Bool {
        guard observedGeneration == generation, !applying else { return false }
        let current = observed.resolvingSymlinksInPath()
        guard current != active.resolvingSymlinksInPath() else {
            candidate = nil
            return false
        }
        guard candidate == current else {
            candidate = current
            firstSeen = now
            return false
        }
        return now.timeIntervalSince(firstSeen) >= 0.5
    }
}
