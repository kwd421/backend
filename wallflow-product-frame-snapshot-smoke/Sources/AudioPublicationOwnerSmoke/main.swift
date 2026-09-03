import Foundation

final class CompletePublication {
    private(set) var snapshotCount = 0
    var latest: Double

    init(latest: Double) {
        self.latest = latest
    }

    func snapshot() -> Double {
        snapshotCount += 1
        return latest
    }
}

struct RendererHistory {
    private(set) var value = 0.0

    mutating func advance(sample: Double) -> Double {
        value = value * 0.75 + sample * 0.25
        return value
    }
}

final class FrameTransaction {
    private var rollbackActions: [() -> Void] = []
    private var completed = false

    func publish(
        install: () -> Void,
        rollback: @escaping () -> Void
    ) {
        precondition(!completed)
        install()
        rollbackActions.append(rollback)
    }

    func rollback() {
        precondition(!completed)
        for action in rollbackActions.reversed() {
            action()
        }
        rollbackActions.removeAll()
        completed = true
    }

    func submit() {
        precondition(!completed)
        rollbackActions.removeAll()
        completed = true
    }
}

final class ProductAudioOwner {
    private var renderer = RendererHistory()

    func prepareFrame(
        publication: CompletePublication,
        transaction: FrameTransaction
    ) -> Double {
        let sample = publication.snapshot()
        let previous = renderer
        var candidate = previous
        let output = candidate.advance(sample: sample)
        transaction.publish(
            install: { [self] in renderer = candidate },
            rollback: { [self] in renderer = previous }
        )
        return output
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let publication = CompletePublication(latest: 1)
let owner = ProductAudioOwner()

let rejected = FrameTransaction()
let rejectedOutput = owner.prepareFrame(
    publication: publication,
    transaction: rejected
)
require(rejectedOutput == 0.25, "first renderer-owned smoothing step changed")
require(publication.snapshotCount == 1, "rejected frame did not snapshot publication exactly once")
rejected.rollback()

let retriedAsNewFrame = FrameTransaction()
let repeatedOutput = owner.prepareFrame(
    publication: publication,
    transaction: retriedAsNewFrame
)
require(repeatedOutput == rejectedOutput, "rollback did not restore renderer audio history")
require(publication.snapshotCount == 2, "second accepted attempt did not take one fresh publication snapshot")
retriedAsNewFrame.submit()

publication.latest = 0.5
let next = FrameTransaction()
let nextOutput = owner.prepareFrame(
    publication: publication,
    transaction: next
)
require(nextOutput == 0.3125, "submitted history was not retained for the next frame")
require(publication.snapshotCount == 3, "next frame observed more than one publication snapshot")
next.submit()

print("PASS: audio publication snapshot and renderer-history transaction ownership")
