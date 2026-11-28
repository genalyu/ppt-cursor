/// A failed write is terminal for its proposal, but must not strand session controls.
enum StagedSubmission {
    case ready, exporting, writing, failed

    var canAccept: Bool { self == .ready }
    var canHandleCommands: Bool { self == .ready || self == .failed }
}
