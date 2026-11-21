import Foundation
import Darwin

struct InferenceTimeout: LocalizedError {
    var errorDescription: String? { "模型响应超时，请继续编辑以重新预测。" }
}

/// Coordinates cancellation with Process.run so a late launch cannot escape a prior cancellation.
public final class PredictionRun: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var timedOut = false
    private var networkTask: URLSessionTask?
    private var process: Process?

    public init() {}

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        networkTask?.cancel()
        if let process { stop(process) }
    }

    func resume(_ task: URLSessionTask) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { task.cancel(); throw CancellationError() }
        networkTask = task
        task.resume()
    }

    // Called with lock held. A CLI can trap SIGTERM while draining its network stream.
    private func stop(_ child: Process) {
        guard child.isRunning else { return }
        child.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self, weak child] in
            guard let self, let child else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.process === child, child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }

    func execute(_ child: Process, timeout: TimeInterval = 60) throws {
        lock.lock()
        guard !cancelled else { lock.unlock(); throw CancellationError() }
        do { try child.run() }
        catch { lock.unlock(); throw error }
        process = child
        lock.unlock()

        let deadline = DispatchWorkItem { [weak self, weak child] in
            guard let self, let child else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard self.process === child, child.isRunning, !self.cancelled else { return }
            self.timedOut = true
            self.stop(child)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        child.waitUntilExit()
        deadline.cancel()
        lock.lock()
        process = nil
        let expired = timedOut
        let discarded = cancelled
        lock.unlock()
        if discarded { throw CancellationError() }
        if expired { throw InferenceTimeout() }
    }
}
