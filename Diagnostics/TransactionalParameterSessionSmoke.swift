import Foundation
import Metal

enum SmokeError: Error, Equatable {
    case noDevice
    case noCommandQueue
    case noCommandBuffer
    case transactionNotEncoding
    case frameAlreadyPending(UInt64)
    case staleFrame(expected: UInt64, actual: UInt64?)
    case invalidCommittedValue(Double)
}

@MainActor
final class FrameTransaction {
    private enum Lifecycle {
        case encoding
        case submitted
        case completed
        case rolledBack
    }

    private struct ExternalMutation {
        let rollback: @MainActor () -> Void
        let complete: @MainActor () -> Void
    }

    let commandBuffer: MTLCommandBuffer
    private var lifecycle: Lifecycle = .encoding
    private var mutations: [ExternalMutation] = []

    init(commandBuffer: MTLCommandBuffer) {
        self.commandBuffer = commandBuffer
    }

    func publishExternalState(
        install: () -> Void,
        rollback: @escaping @MainActor () -> Void,
        complete: @escaping @MainActor () -> Void
    ) throws {
        guard lifecycle == .encoding else {
            throw SmokeError.transactionNotEncoding
        }
        install()
        mutations.append(ExternalMutation(
            rollback: rollback,
            complete: complete
        ))
    }

    func rollback() throws {
        guard lifecycle == .encoding else {
            throw SmokeError.transactionNotEncoding
        }
        for mutation in mutations.reversed() {
            mutation.rollback()
        }
        mutations.removeAll()
        lifecycle = .rolledBack
    }

    func submitAndWait() throws {
        guard lifecycle == .encoding else {
            throw SmokeError.transactionNotEncoding
        }
        commandBuffer.addCompletedHandler(
            Self.makeCompletionHandler(transaction: self)
        )
        lifecycle = .submitted
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        finishCompletion(succeeded: commandBuffer.status == .completed)
    }

    private func finishCompletion(succeeded: Bool) {
        guard lifecycle == .submitted else { return }
        precondition(succeeded)
        for mutation in mutations {
            mutation.complete()
        }
        mutations.removeAll()
        lifecycle = .completed
    }

    nonisolated private static func makeCompletionHandler(
        transaction: FrameTransaction
    ) -> MTLCommandBufferHandler {
        { commandBuffer in
            let succeeded = commandBuffer.status == .completed
            Task { @MainActor in
                transaction.finishCompletion(succeeded: succeeded)
            }
        }
    }
}

@MainActor
final class ParameterSession {
    @MainActor
    final class PreparedFrame {
        private weak var session: ParameterSession?
        private let generation: UInt64
        private let resolvedValue: Double

        fileprivate init(
            session: ParameterSession,
            generation: UInt64,
            resolvedValue: Double
        ) {
            self.session = session
            self.generation = generation
            self.resolvedValue = resolvedValue
        }

        func value() throws -> Double {
            let actual = session?.pendingGeneration
            guard actual == generation else {
                throw SmokeError.staleFrame(
                    expected: generation,
                    actual: actual
                )
            }
            return resolvedValue
        }
    }

    private var runtimeValue: Double = 0
    private var generation: UInt64 = 0
    fileprivate var pendingGeneration: UInt64?

    func prepareFrame(
        transaction: FrameTransaction,
        delta: Double
    ) throws -> PreparedFrame {
        if let pendingGeneration {
            throw SmokeError.frameAlreadyPending(pendingGeneration)
        }
        let previousValue = runtimeValue
        let nextValue = runtimeValue + delta
        let nextGeneration = generation + 1

        try transaction.publishExternalState(
            install: { [self] in
                runtimeValue = nextValue
                generation = nextGeneration
                pendingGeneration = nextGeneration
            },
            rollback: { [self] in
                precondition(generation == nextGeneration)
                precondition(pendingGeneration == nextGeneration)
                runtimeValue = previousValue
                pendingGeneration = nil
            },
            complete: { [self] in
                precondition(generation == nextGeneration)
                precondition(pendingGeneration == nextGeneration)
                pendingGeneration = nil
            }
        )
        return PreparedFrame(
            session: self,
            generation: nextGeneration,
            resolvedValue: nextValue
        )
    }
}

func requireSmokeError(
    _ expected: SmokeError,
    operation: () throws -> Void
) {
    do {
        try operation()
        preconditionFailure("Expected error \(expected)")
    } catch let actual as SmokeError {
        precondition(actual == expected, "Expected \(expected), got \(actual)")
    } catch {
        preconditionFailure("Unexpected error \(error)")
    }
}

@main
struct Main {
    @MainActor
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SmokeError.noDevice
        }
        guard let queue = device.makeCommandQueue() else {
            throw SmokeError.noCommandQueue
        }
        let session = ParameterSession()

        guard let firstBuffer = queue.makeCommandBuffer() else {
            throw SmokeError.noCommandBuffer
        }
        let firstTransaction = FrameTransaction(commandBuffer: firstBuffer)
        let firstFrame = try session.prepareFrame(
            transaction: firstTransaction,
            delta: 1
        )
        let firstValue = try firstFrame.value()
        precondition(firstValue == 1)
        requireSmokeError(.frameAlreadyPending(1)) {
            _ = try session.prepareFrame(
                transaction: firstTransaction,
                delta: 1
            )
        }
        try firstTransaction.rollback()
        requireSmokeError(.staleFrame(expected: 1, actual: nil)) {
            _ = try firstFrame.value()
        }

        guard let secondBuffer = queue.makeCommandBuffer() else {
            throw SmokeError.noCommandBuffer
        }
        let secondTransaction = FrameTransaction(commandBuffer: secondBuffer)
        let secondFrame = try session.prepareFrame(
            transaction: secondTransaction,
            delta: 1
        )
        let secondValue = try secondFrame.value()
        precondition(secondValue == 1)
        requireSmokeError(.staleFrame(expected: 1, actual: 2)) {
            _ = try firstFrame.value()
        }
        try secondTransaction.submitAndWait()
        requireSmokeError(.staleFrame(expected: 2, actual: nil)) {
            _ = try secondFrame.value()
        }

        guard let thirdBuffer = queue.makeCommandBuffer() else {
            throw SmokeError.noCommandBuffer
        }
        let thirdTransaction = FrameTransaction(commandBuffer: thirdBuffer)
        let thirdFrame = try session.prepareFrame(
            transaction: thirdTransaction,
            delta: 1
        )
        let committedValue = try thirdFrame.value()
        guard committedValue == 2 else {
            throw SmokeError.invalidCommittedValue(committedValue)
        }
        try thirdTransaction.rollback()

        print("transactional parameter session OK")
    }
}
