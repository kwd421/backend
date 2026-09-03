import Foundation

private enum AudioHistoryError: Error, Equatable {
    case invalidFrameTime
    case transactionClosed
}

private final class AudioPublication: @unchecked Sendable {
    private let lock = NSLock()
    private var sample: Double

    init(sample: Double) {
        self.sample = sample
    }

    func publish(_ sample: Double) {
        lock.lock()
        self.sample = sample
        lock.unlock()
    }

    func snapshot() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return sample
    }
}

private struct AudioRenderProcessor: Sendable {
    let publication: AudioPublication
    private(set) var history: Double = 0

    mutating func advance(frameTime: Double) throws -> Double {
        guard frameTime.isFinite, frameTime > 0, frameTime <= 0.25 else {
            throw AudioHistoryError.invalidFrameTime
        }
        let amount = min(frameTime * 20, 1)
        history += (publication.snapshot() - history) * amount
        return history
    }
}

@MainActor
private final class FrameTransaction {
    private enum State {
        case encoding
        case submitted
        case rolledBack
    }

    private struct Mutation {
        let rollback: @MainActor () -> Void
        let complete: @MainActor () -> Void
    }

    private var state = State.encoding
    private var mutations: [Mutation] = []

    func publishExternalState(
        install: () -> Void,
        rollback: @escaping @MainActor () -> Void,
        complete: @escaping @MainActor () -> Void
    ) throws {
        guard state == .encoding else {
            throw AudioHistoryError.transactionClosed
        }
        install()
        mutations.append(Mutation(rollback: rollback, complete: complete))
    }

    func rollback() throws {
        guard state == .encoding else {
            throw AudioHistoryError.transactionClosed
        }
        for mutation in mutations.reversed() {
            mutation.rollback()
        }
        mutations.removeAll()
        state = .rolledBack
    }

    func submitAndComplete() throws {
        guard state == .encoding else {
            throw AudioHistoryError.transactionClosed
        }
        state = .submitted
        for mutation in mutations {
            mutation.complete()
        }
        mutations.removeAll()
    }
}

@MainActor
private final class ProductAudioRuntime {
    private var processor: AudioRenderProcessor

    init(publication: AudioPublication) {
        processor = AudioRenderProcessor(publication: publication)
    }

    func prepareFrame(
        frameTime: Double,
        transaction: FrameTransaction
    ) throws -> Double {
        let previous = processor
        var candidate = previous
        let output = try candidate.advance(frameTime: frameTime)
        try transaction.publishExternalState(
            install: { [self] in
                processor = candidate
            },
            rollback: { [self] in
                processor = previous
            },
            complete: {}
        )
        return output
    }
}

@main
private struct AudioHistorySmoke {
    @MainActor
    static func main() throws {
        try verifyRollbackRestoresHistory()
        try verifySubmissionRetainsHistory()
        try verifyInvalidFrameDoesNotMutateHistory()
        print("wallflow-audio-history-smoke: ok")
    }

    @MainActor
    private static func verifyRollbackRestoresHistory() throws {
        let publication = AudioPublication(sample: 1)
        let runtime = ProductAudioRuntime(publication: publication)

        let firstTransaction = FrameTransaction()
        let first = try runtime.prepareFrame(
            frameTime: 0.01,
            transaction: firstTransaction
        )
        try firstTransaction.rollback()

        let secondTransaction = FrameTransaction()
        let second = try runtime.prepareFrame(
            frameTime: 0.01,
            transaction: secondTransaction
        )
        precondition(first == second)
        try secondTransaction.rollback()
    }

    @MainActor
    private static func verifySubmissionRetainsHistory() throws {
        let publication = AudioPublication(sample: 1)
        let runtime = ProductAudioRuntime(publication: publication)

        let firstTransaction = FrameTransaction()
        let first = try runtime.prepareFrame(
            frameTime: 0.01,
            transaction: firstTransaction
        )
        try firstTransaction.submitAndComplete()

        let secondTransaction = FrameTransaction()
        let second = try runtime.prepareFrame(
            frameTime: 0.01,
            transaction: secondTransaction
        )
        precondition(second > first)
        try secondTransaction.rollback()
    }

    @MainActor
    private static func verifyInvalidFrameDoesNotMutateHistory() throws {
        let publication = AudioPublication(sample: 1)
        let runtime = ProductAudioRuntime(publication: publication)
        let invalidTransaction = FrameTransaction()

        do {
            _ = try runtime.prepareFrame(
                frameTime: 0,
                transaction: invalidTransaction
            )
            fatalError("invalid frame time was accepted")
        } catch AudioHistoryError.invalidFrameTime {
            try invalidTransaction.rollback()
        }

        let validTransaction = FrameTransaction()
        let first = try runtime.prepareFrame(
            frameTime: 0.01,
            transaction: validTransaction
        )
        precondition(abs(first - 0.2) < 0.000_001)
        try validTransaction.rollback()
    }
}
