import Foundation

private struct ScriptCallbacks: Sendable {
    let hasApplyUserProperties: Bool
}

private struct UserProperties: Equatable, Sendable {
    let rawValues: [String: String]
}

private enum ScriptRuntimeError: Error, Equatable {
    case propertiesChangedWithoutEventAdapter
    case terminalFailure(String)
}

private enum SessionFailure: Error {
    case intentionalUpdateFailure
}

@MainActor
private final class DeterministicScriptSession {
    enum Event: Equatable {
        case initialize
        case apply([String: String])
        case update
    }

    private(set) var generation = 0
    private(set) var value = 1
    private(set) var events: [Event] = []
    private(set) var updateCallCount = 0
    private let failingUpdateCall: Int?

    init(failingUpdateCall: Int? = nil) {
        self.failingUpdateCall = failingUpdateCall
    }

    func initializeScripts() -> Int {
        events.append(.initialize)
        value = 9
        generation += 1
        return generation
    }

    func applyUserProperties(_ properties: [String: String]) -> Int {
        events.append(.apply(properties))
        value = Int(properties["mode"] ?? "") ?? value
        generation += 1
        return generation
    }

    func updateScripts() throws -> Int {
        events.append(.update)
        updateCallCount += 1
        if updateCallCount == failingUpdateCall {
            throw SessionFailure.intentionalUpdateFailure
        }
        value += 1
        generation += 1
        return generation
    }
}

@MainActor
private final class ProductScriptRuntime {
    private let session: DeterministicScriptSession
    private let initialProperties: UserProperties
    private var currentGeneration: Int
    private var terminalError: ScriptRuntimeError?

    init(
        callbacks: [ScriptCallbacks],
        session: DeterministicScriptSession,
        initialProperties: UserProperties
    ) {
        self.session = session
        self.initialProperties = initialProperties
        var generation = session.initializeScripts()
        if callbacks.contains(where: \.hasApplyUserProperties) {
            generation = session.applyUserProperties(initialProperties.rawValues)
        }
        currentGeneration = generation
    }

    func prepareFrame(properties: UserProperties) throws -> Int {
        if let terminalError {
            throw terminalError
        }
        guard properties == initialProperties else {
            throw ScriptRuntimeError.propertiesChangedWithoutEventAdapter
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
        try verifyInitialPropertiesFollowInitAndPrecedeUpdate()
        try verifyChangedPropertiesFailBeforeFrameAdmission()
        try verifyRollbackDoesNotAdvanceScripts()
        try verifySubmittedFrameAdvancesExactlyOnce()
        try verifyPostSubmitFailurePoisonsNextFrame()
        print("wallflow-script-lifecycle-smoke: ok")
    }

    @MainActor
    private static func verifyInitialPropertiesFollowInitAndPrecedeUpdate() throws {
        let session = DeterministicScriptSession()
        let properties = UserProperties(rawValues: ["mode": "2"])
        let runtime = ProductScriptRuntime(
            callbacks: [
                ScriptCallbacks(hasApplyUserProperties: false),
                ScriptCallbacks(hasApplyUserProperties: true)
            ],
            session: session,
            initialProperties: properties
        )

        let firstGeneration = try runtime.prepareFrame(properties: properties)
        precondition(firstGeneration == 2)
        precondition(session.value == 2)
        precondition(session.events == [
            .initialize,
            .apply(["mode": "2"])
        ])

        let transaction = FrameTransaction()
        try transaction.publishCompletion {
            runtime.completeSubmittedFrame()
        }
        try transaction.submitAndComplete()

        let secondGeneration = try runtime.prepareFrame(properties: properties)
        precondition(secondGeneration == 3)
        precondition(session.value == 3)
        precondition(session.events == [
            .initialize,
            .apply(["mode": "2"]),
            .update
        ])
    }

    @MainActor
    private static func verifyChangedPropertiesFailBeforeFrameAdmission() throws {
        let session = DeterministicScriptSession()
        let initial = UserProperties(rawValues: ["mode": "1"])
        let runtime = ProductScriptRuntime(
            callbacks: [ScriptCallbacks(hasApplyUserProperties: true)],
            session: session,
            initialProperties: initial
        )

        do {
            _ = try runtime.prepareFrame(
                properties: UserProperties(rawValues: ["mode": "2"])
            )
            fatalError("a changed property snapshot bypassed its missing event adapter")
        } catch ScriptRuntimeError.propertiesChangedWithoutEventAdapter {
        }
        precondition(session.events == [
            .initialize,
            .apply(["mode": "1"])
        ])
        precondition(session.updateCallCount == 0)
        let acceptedGeneration = try runtime.prepareFrame(properties: initial)
        precondition(acceptedGeneration == 2)
    }

    @MainActor
    private static func verifyRollbackDoesNotAdvanceScripts() throws {
        let session = DeterministicScriptSession()
        let properties = UserProperties(rawValues: [:])
        let runtime = ProductScriptRuntime(
            callbacks: [ScriptCallbacks(hasApplyUserProperties: false)],
            session: session,
            initialProperties: properties
        )
        let initial = try runtime.prepareFrame(properties: properties)
        precondition(initial == 1)
        precondition(session.events == [.initialize])

        let transaction = FrameTransaction()
        try transaction.publishCompletion {
            runtime.completeSubmittedFrame()
        }
        try transaction.rollback()

        precondition(session.updateCallCount == 0)
        let afterRollback = try runtime.prepareFrame(properties: properties)
        precondition(afterRollback == initial)
    }

    @MainActor
    private static func verifySubmittedFrameAdvancesExactlyOnce() throws {
        let session = DeterministicScriptSession()
        let properties = UserProperties(rawValues: [:])
        let runtime = ProductScriptRuntime(
            callbacks: [ScriptCallbacks(hasApplyUserProperties: false)],
            session: session,
            initialProperties: properties
        )
        let initial = try runtime.prepareFrame(properties: properties)

        let transaction = FrameTransaction()
        try transaction.publishCompletion {
            runtime.completeSubmittedFrame()
        }
        try transaction.submitAndComplete()

        precondition(session.updateCallCount == 1)
        let afterSubmission = try runtime.prepareFrame(properties: properties)
        precondition(afterSubmission == initial + 1)
    }

    @MainActor
    private static func verifyPostSubmitFailurePoisonsNextFrame() throws {
        let session = DeterministicScriptSession(failingUpdateCall: 1)
        let properties = UserProperties(rawValues: [:])
        let runtime = ProductScriptRuntime(
            callbacks: [ScriptCallbacks(hasApplyUserProperties: false)],
            session: session,
            initialProperties: properties
        )
        let transaction = FrameTransaction()
        try transaction.publishCompletion {
            runtime.completeSubmittedFrame()
        }
        try transaction.submitAndComplete()

        do {
            _ = try runtime.prepareFrame(properties: properties)
            fatalError("a post-submit script failure did not poison the next frame")
        } catch ScriptRuntimeError.terminalFailure(let message) {
            precondition(!message.isEmpty)
        }
    }
}
