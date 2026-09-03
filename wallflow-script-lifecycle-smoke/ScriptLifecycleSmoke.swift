import Foundation

private struct ScriptCallbacks: Sendable {
    let hasApplyUserProperties: Bool
}

private enum ScriptRuntimeError: Error, Equatable {
    case propertyEventAdapterMissing(callbackCount: Int)
    case terminalFailure(String)
}

private enum SessionFailure: Error {
    case intentionalUpdateFailure
}

@MainActor
private final class DeterministicScriptSession {
    private(set) var generation = 0
    private(set) var updateCallCount = 0
    private let failingUpdateCall: Int?

    init(failingUpdateCall: Int? = nil) {
        self.failingUpdateCall = failingUpdateCall
    }

    func initializeScripts() -> Int {
        generation += 1
        return generation
    }

    func updateScripts() throws -> Int {
        updateCallCount += 1
        if updateCallCount == failingUpdateCall {
            throw SessionFailure.intentionalUpdateFailure
        }
        generation += 1
        return generation
    }
}

@MainActor
private final class ProductScriptRuntime {
    private let session: DeterministicScriptSession
    private var currentGeneration: Int
    private var terminalError: ScriptRuntimeError?

    init(
        callbacks: [ScriptCallbacks],
        session: DeterministicScriptSession
    ) throws {
        let unsupportedCount = callbacks.lazy.filter {
            $0.hasApplyUserProperties
        }.count
        guard unsupportedCount == 0 else {
            throw ScriptRuntimeError.propertyEventAdapterMissing(
                callbackCount: unsupportedCount
            )
        }
        self.session = session
        currentGeneration = session.initializeScripts()
    }

    func snapshot() throws -> Int {
        if let terminalError {
            throw terminalError
        }
        return currentGeneration
    }

    func completeSubmittedFrame() {
        guard terminalError == nil else { return }
        do {
            currentGeneration = try session.updateScripts()
        } catch {
            terminalError = .terminalFailure(error.localizedDescription)
        }
    }
}

private enum TransactionError: Error {
    case noLongerEncoding
}

@MainActor
private final class FrameTransaction {
    private enum State {
        case encoding
        case submitted
        case rolledBack
    }

    private var state = State.encoding
    private var completion: (@MainActor () -> Void)?

    func publishCompletion(_ completion: @escaping @MainActor () -> Void) throws {
        guard state == .encoding else {
            throw TransactionError.noLongerEncoding
        }
        self.completion = completion
    }

    func rollback() throws {
        guard state == .encoding else {
            throw TransactionError.noLongerEncoding
        }
        state = .rolledBack
        completion = nil
    }

    func submitAndComplete() throws {
        guard state == .encoding else {
            throw TransactionError.noLongerEncoding
        }
        state = .submitted
        let callback = completion
        completion = nil
        callback?()
    }
}

@main
private struct ScriptLifecycleSmoke {
    @MainActor
    static func main() throws {
        try verifyApplyUserPropertiesFailsClosed()
        try verifyRollbackDoesNotAdvanceScripts()
        try verifySubmittedFrameAdvancesExactlyOnce()
        try verifyPostSubmitFailurePoisonsNextFrame()
        print("wallflow-script-lifecycle-smoke: ok")
    }

    @MainActor
    private static func verifyApplyUserPropertiesFailsClosed() throws {
        do {
            _ = try ProductScriptRuntime(
                callbacks: [
                    ScriptCallbacks(hasApplyUserProperties: true),
                    ScriptCallbacks(hasApplyUserProperties: false),
                    ScriptCallbacks(hasApplyUserProperties: true)
                ],
                session: DeterministicScriptSession()
            )
            fatalError("applyUserProperties callbacks were silently accepted")
        } catch ScriptRuntimeError.propertyEventAdapterMissing(let callbackCount) {
            precondition(callbackCount == 2)
        }
    }

    @MainActor
    private static func verifyRollbackDoesNotAdvanceScripts() throws {
        let session = DeterministicScriptSession()
        let runtime = try ProductScriptRuntime(
            callbacks: [ScriptCallbacks(hasApplyUserProperties: false)],
            session: session
        )
        let initial = try runtime.snapshot()
        precondition(initial == 1)

        let transaction = FrameTransaction()
        try transaction.publishCompletion {
            runtime.completeSubmittedFrame()
        }
        try transaction.rollback()

        precondition(session.updateCallCount == 0)
        let afterRollback = try runtime.snapshot()
        precondition(afterRollback == initial)
    }

    @MainActor
    private static func verifySubmittedFrameAdvancesExactlyOnce() throws {
        let session = DeterministicScriptSession()
        let runtime = try ProductScriptRuntime(
            callbacks: [ScriptCallbacks(hasApplyUserProperties: false)],
            session: session
        )
        let initial = try runtime.snapshot()

        let transaction = FrameTransaction()
        try transaction.publishCompletion {
            runtime.completeSubmittedFrame()
        }
        try transaction.submitAndComplete()

        precondition(session.updateCallCount == 1)
        let afterSubmission = try runtime.snapshot()
        precondition(afterSubmission == initial + 1)
    }

    @MainActor
    private static func verifyPostSubmitFailurePoisonsNextFrame() throws {
        let session = DeterministicScriptSession(failingUpdateCall: 1)
        let runtime = try ProductScriptRuntime(
            callbacks: [ScriptCallbacks(hasApplyUserProperties: false)],
            session: session
        )
        let transaction = FrameTransaction()
        try transaction.publishCompletion {
            runtime.completeSubmittedFrame()
        }
        try transaction.submitAndComplete()

        do {
            _ = try runtime.snapshot()
            fatalError("a post-submit script failure did not poison the next frame")
        } catch ScriptRuntimeError.terminalFailure(let message) {
            precondition(!message.isEmpty)
        }
    }
}
