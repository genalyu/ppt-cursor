import Foundation

/// Coordinates cancellation with Process.run so a late launch cannot escape a prior cancellation.
public final class PredictionRun: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var networkTask: URLSessionTask?
    private var process: Process?

    public init() {}

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        networkTask?.cancel()
        if let process, process.isRunning { process.terminate() }
    }

    func resume(_ task: URLSessionTask) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { task.cancel(); throw CancellationError() }
        networkTask = task
        task.resume()
    }

    func execute(_ child: Process) throws {
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        do { try child.run() }
        catch { lock.unlock(); throw error }
        process = child
        lock.unlock()

        child.waitUntilExit()
        lock.lock()
        process = nil
        let discarded = cancelled
        lock.unlock()
        if discarded { throw CancellationError() }
    }
}
