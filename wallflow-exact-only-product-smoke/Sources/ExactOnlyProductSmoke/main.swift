import Foundation

private struct OriginalSceneArchive: Sendable {
    let effectProgramCount: Int
}

private struct ProductPlan: Equatable, Sendable {
    let identity: Int
}

private enum ExactProductError: Error, Equatable, Sendable {
    case missingOriginalArchive
    case missingProductPlan
    case planChanged
    case encodingFailed
}

@MainActor
private final class ExactRuntime {
    let archive: OriginalSceneArchive
    let plan: ProductPlan
    private(set) var clock = 0

    init(archive: OriginalSceneArchive, plan: ProductPlan) {
        self.archive = archive
        self.plan = plan
    }

    func prepareFrame(plan: ProductPlan) throws -> ExactFrameTransaction {
        guard plan == self.plan else {
            throw ExactProductError.planChanged
        }
        let previousClock = clock
        clock += 1
        return ExactFrameTransaction(
            rollback: { [self] in clock = previousClock }
        )
    }
}

@MainActor
private final class ExactFrameTransaction {
    private enum State {
        case encoding
        case submitted
        case rolledBack
    }

    private var state: State = .encoding
    private let rollbackAction: @MainActor () -> Void

    init(rollback: @escaping @MainActor () -> Void) {
        rollbackAction = rollback
    }

    func submit(
        finalize: () throws -> Void,
        submit: () -> Void
    ) throws {
        precondition(state == .encoding)
        try finalize()
        submit()
        state = .submitted
    }

    func rollback() {
        precondition(state == .encoding)
        rollbackAction()
        state = .rolledBack
    }
}

@MainActor
private final class ExactProductOwner {
    let runtime: ExactRuntime
    private(set) var submitCount = 0
    private(set) var finalizeCount = 0

    init(runtime: ExactRuntime) {
        self.runtime = runtime
    }

    func render(
        plan: ProductPlan,
        failEncoding: Bool
    ) throws {
        let transaction = try runtime.prepareFrame(plan: plan)
        do {
            if failEncoding {
                throw ExactProductError.encodingFailed
            }
            try transaction.submit(
                finalize: { [self] in finalizeCount += 1 },
                submit: { [self] in submitCount += 1 }
            )
        } catch {
            transaction.rollback()
            throw error
        }
    }
}

@MainActor
private enum ExactProductFactory {
    static func make(
        archive: OriginalSceneArchive?,
        plan: ProductPlan?
    ) throws -> ExactProductOwner {
        guard let archive else {
            throw ExactProductError.missingOriginalArchive
        }
        guard let plan else {
            throw ExactProductError.missingProductPlan
        }
        // Zero effects is a valid exact static-ImageLayer package. It is not eligibility for
        // another backend.
        precondition(archive.effectProgramCount >= 0)
        return ExactProductOwner(
            runtime: ExactRuntime(archive: archive, plan: plan)
        )
    }
}

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private struct ExactOnlyProductSmoke {
    @MainActor
    static func main() throws {
        let plan = ProductPlan(identity: 7)

        let staticOwner = try ExactProductFactory.make(
            archive: OriginalSceneArchive(effectProgramCount: 0),
            plan: plan
        )
        require(
            staticOwner.runtime.archive.effectProgramCount == 0,
            "zero-effect package did not remain on the exact runtime"
        )
        try staticOwner.render(plan: plan, failEncoding: false)
        require(staticOwner.submitCount == 1, "exact static frame did not submit once")
        require(staticOwner.finalizeCount == 1, "exact static frame did not finalize once")
        require(staticOwner.runtime.clock == 1, "exact static frame lost clock state")

        let failingOwner = try ExactProductFactory.make(
            archive: OriginalSceneArchive(effectProgramCount: 3),
            plan: plan
        )
        do {
            try failingOwner.render(plan: plan, failEncoding: true)
            require(false, "failing exact frame was accepted")
        } catch ExactProductError.encodingFailed {
        }
        require(failingOwner.submitCount == 0, "failing exact frame submitted")
        require(failingOwner.finalizeCount == 0, "failing exact frame finalized")
        require(failingOwner.runtime.clock == 0, "failing exact frame advanced clock")

        do {
            _ = try ExactProductFactory.make(archive: nil, plan: plan)
            require(false, "missing original archive was accepted")
        } catch ExactProductError.missingOriginalArchive {
        }

        do {
            _ = try ExactProductFactory.make(
                archive: OriginalSceneArchive(effectProgramCount: 1),
                plan: nil
            )
            require(false, "missing product plan was accepted")
        } catch ExactProductError.missingProductPlan {
        }

        let staleOwner = try ExactProductFactory.make(
            archive: OriginalSceneArchive(effectProgramCount: 1),
            plan: plan
        )
        do {
            try staleOwner.render(
                plan: ProductPlan(identity: 8),
                failEncoding: false
            )
            require(false, "changed product plan was accepted")
        } catch ExactProductError.planChanged {
        }
        require(staleOwner.submitCount == 0, "stale plan submitted")
        require(staleOwner.finalizeCount == 0, "stale plan finalized")
        require(staleOwner.runtime.clock == 0, "stale plan advanced clock")

        print("PASS: exact-only product ownership has no legacy eligibility or fallback")
    }
}
