import Foundation

enum StreamError: Error, Equatable, Sendable {
    case mismatchedChannelFrameCount(left: Int, right: Int)
}

final class Publication: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        case block(left: [Float], right: [Float])
        case silence
    }

    private let lock = NSLock()
    private var events: [Event] = []

    func publish(left: [Float], right: [Float]) {
        lock.withLock { events.append(.block(left: left, right: right)) }
    }

    func publishSilence() {
        lock.withLock { events.append(.silence) }
    }

    func snapshot() -> [Event] {
        lock.withLock { events }
    }
}

final class CaptureStream: @unchecked Sendable {
    enum Lifecycle: Equatable, Sendable {
        case running
        case paused
        case stopped
    }

    struct Status: Equatable, Sendable {
        let lifecycle: Lifecycle
        let pendingFrameCount: Int
        let publishedBlockCount: UInt64
        let failure: StreamError?
    }

    private struct Buffer {
        private var storage: [Float] = []
        private var startIndex = 0

        var count: Int { storage.count - startIndex }

        mutating func append(_ values: [Float]) {
            storage.append(contentsOf: values)
        }

        mutating func take(_ count: Int) -> [Float]? {
            guard self.count >= count else { return nil }
            let end = startIndex + count
            let result = Array(storage[startIndex..<end])
            startIndex = end
            if startIndex == storage.count {
                storage.removeAll(keepingCapacity: true)
                startIndex = 0
            }
            return result
        }

        mutating func clear() {
            storage.removeAll(keepingCapacity: true)
            startIndex = 0
        }
    }

    private struct Worker {
        var lifecycle: Lifecycle = .running
        var left = Buffer()
        var right = Buffer()
        var publishedBlockCount: UInt64 = 0
        var failure: StreamError?
    }

    let publication: Publication
    let captureFrameCount: Int

    private let queue = DispatchQueue(
        label: "public.wallflow.capture-stream-smoke",
        qos: .userInitiated
    )
    private var worker = Worker()

    init(captureFrameCount: Int, publication: Publication) {
        precondition(captureFrameCount > 0)
        self.captureFrameCount = captureFrameCount
        self.publication = publication
    }

    func enqueue(left: [Float], right: [Float]? = nil) {
        queue.async { [self, left, right] in
            guard worker.failure == nil, worker.lifecycle == .running else { return }
            if let right, right.count != left.count {
                worker.failure = .mismatchedChannelFrameCount(
                    left: left.count,
                    right: right.count
                )
                worker.left.clear()
                worker.right.clear()
                return
            }
            worker.left.append(left)
            worker.right.append(right ?? left)
            while worker.left.count >= captureFrameCount {
                guard let leftBlock = worker.left.take(captureFrameCount),
                      let rightBlock = worker.right.take(captureFrameCount) else {
                    preconditionFailure("channel FIFO lost synchronization")
                }
                if leftBlock.allSatisfy({ $0 == 0 })
                    && rightBlock.allSatisfy({ $0 == 0 }) {
                    publication.publishSilence()
                } else {
                    publication.publish(left: leftBlock, right: rightBlock)
                }
                worker.publishedBlockCount += 1
            }
        }
    }

    func pause() {
        queue.async { [self] in
            guard worker.failure == nil, worker.lifecycle == .running else { return }
            worker.left.clear()
            worker.right.clear()
            worker.lifecycle = .paused
            publication.publishSilence()
        }
    }

    func resume() {
        queue.async { [self] in
            guard worker.failure == nil, worker.lifecycle == .paused else { return }
            worker.left.clear()
            worker.right.clear()
            worker.lifecycle = .running
        }
    }

    func stop() {
        queue.async { [self] in
            guard worker.lifecycle != .stopped else { return }
            worker.left.clear()
            worker.right.clear()
            worker.lifecycle = .stopped
            guard worker.failure == nil else { return }
            publication.publishSilence()
        }
    }

    func synchronize() throws -> Status {
        let status = queue.sync {
            Status(
                lifecycle: worker.lifecycle,
                pendingFrameCount: worker.left.count,
                publishedBlockCount: worker.publishedBlockCount,
                failure: worker.failure
            )
        }
        if let failure = status.failure {
            throw failure
        }
        return status
    }

    func status() -> Status {
        queue.sync {
            Status(
                lifecycle: worker.lifecycle,
                pendingFrameCount: worker.left.count,
                publishedBlockCount: worker.publishedBlockCount,
                failure: worker.failure
            )
        }
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let publication = Publication()
let stream = CaptureStream(captureFrameCount: 8, publication: publication)

stream.enqueue(left: [1, 2, 3])
let partial = try stream.synchronize()
require(partial.pendingFrameCount == 3, "partial callback was not retained")
require(partial.publishedBlockCount == 0, "partial callback published early")
require(publication.snapshot().isEmpty, "publication changed before a complete block")

stream.enqueue(left: [4, 5, 6, 7, 8, 9, 10])
let complete = try stream.synchronize()
require(complete.pendingFrameCount == 2, "uneven callback tail was not retained")
require(complete.publishedBlockCount == 1, "complete block was not published once")
require(publication.snapshot() == [
    .block(left: [1, 2, 3, 4, 5, 6, 7, 8], right: [1, 2, 3, 4, 5, 6, 7, 8])
], "FIFO block order changed")

stream.pause()
let paused = try stream.synchronize()
require(paused.lifecycle == .paused, "pause lifecycle was not installed")
require(paused.pendingFrameCount == 0, "pause retained a cross-boundary partial block")
require(publication.snapshot().last == .silence, "pause did not publish explicit silence")

stream.enqueue(left: Array(repeating: 7, count: 8))
let pausedAfterCallback = try stream.synchronize()
require(pausedAfterCallback.publishedBlockCount == 1, "paused callback was consumed")

stream.resume()
stream.enqueue(left: Array(repeating: 0, count: 8))
let resumed = try stream.synchronize()
require(resumed.lifecycle == .running, "resume lifecycle was not installed")
require(resumed.publishedBlockCount == 2, "resumed complete block was not consumed")
require(publication.snapshot().last == .silence, "all-zero block was not explicit silence")

let beforeFailure = publication.snapshot()
stream.enqueue(left: [1, 2, 3], right: [1, 2])
do {
    _ = try stream.synchronize()
    require(false, "mismatched stereo callback was accepted")
} catch StreamError.mismatchedChannelFrameCount(let left, let right) {
    require(left == 3 && right == 2, "mismatched callback diagnostics changed")
}
require(publication.snapshot() == beforeFailure, "failure replaced the last complete publication")

stream.enqueue(left: Array(repeating: 1, count: 8))
require(stream.status().publishedBlockCount == 2, "terminal stream revived after failure")

let stopPublication = Publication()
let stopStream = CaptureStream(captureFrameCount: 4, publication: stopPublication)
stopStream.enqueue(left: [1, 2, 3, 4])
let beforeStop = try stopStream.synchronize()
require(beforeStop.publishedBlockCount == 1, "stop fixture did not publish")
stopStream.stop()
let stopped = try stopStream.synchronize()
require(stopped.lifecycle == .stopped, "stop lifecycle was not installed")
require(stopPublication.snapshot().last == .silence, "healthy stop did not publish silence")
stopStream.enqueue(left: [5, 6, 7, 8])
let afterStopCallback = try stopStream.synchronize()
require(afterStopCallback == stopped, "stopped stream accepted a later callback")

print("PASS: PCM capture FIFO, lifecycle, and failure publication ownership")
