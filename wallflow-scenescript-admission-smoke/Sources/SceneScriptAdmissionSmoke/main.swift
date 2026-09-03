import Foundation

struct SourceRange: Hashable, Sendable {
    let lower: Int
    let upper: Int
}

struct EffectScriptOwner: Equatable, Sendable {
    let objectIndex: Int
    let effectIndex: Int
    let passIndex: Int
    let materialKey: String
}

enum ScriptOwnership: Equatable, Sendable {
    case exactEffectParameter(EffectScriptOwner)
    case unclaimed
}

struct ScriptOccurrence: Equatable, Sendable {
    let index: Int
    let path: String
    let range: SourceRange
    let source: String
    let ownership: ScriptOwnership
}

enum ScriptAdmissionError: Error, Equatable, Sendable {
    case duplicateExactOwner(SourceRange)
    case missingExactOccurrence(SourceRange)
    case unsupported([ScriptOccurrence])
}

struct ScriptInventory: Equatable, Sendable {
    let occurrences: [ScriptOccurrence]

    var unsupported: [ScriptOccurrence] {
        occurrences.filter { occurrence in
            if case .unclaimed = occurrence.ownership {
                return true
            }
            return false
        }
    }
}

enum ScriptInventoryCompiler {
    static func compile(
        authored: [(path: String, range: SourceRange, source: String)],
        exactOwners: [(range: SourceRange, owner: EffectScriptOwner)]
    ) throws -> ScriptInventory {
        var owners: [SourceRange: EffectScriptOwner] = [:]
        for entry in exactOwners {
            guard owners.updateValue(entry.owner, forKey: entry.range) == nil else {
                throw ScriptAdmissionError.duplicateExactOwner(entry.range)
            }
        }

        var matched: Set<SourceRange> = []
        let occurrences = authored.enumerated().map { index, entry in
            let ownership: ScriptOwnership
            if let owner = owners[entry.range] {
                matched.insert(entry.range)
                ownership = .exactEffectParameter(owner)
            } else {
                ownership = .unclaimed
            }
            return ScriptOccurrence(
                index: index,
                path: entry.path,
                range: entry.range,
                source: entry.source,
                ownership: ownership
            )
        }
        if let missing = owners.keys.first(where: { !matched.contains($0) }) {
            throw ScriptAdmissionError.missingExactOccurrence(missing)
        }
        return ScriptInventory(occurrences: occurrences)
    }

    static func validate(_ inventory: ScriptInventory) throws {
        guard inventory.unsupported.isEmpty else {
            throw ScriptAdmissionError.unsupported(inventory.unsupported)
        }
    }
}

final class MockRendererFactory {
    private(set) var creationCount = 0

    func make(inventory: ScriptInventory) throws {
        try ScriptInventoryCompiler.validate(inventory)
        creationCount += 1
    }
}

struct ExactRuntime: Equatable, Sendable {
    let authoredEffectCount: Int
}

enum ExactRuntimeFactoryError: Error, Equatable, Sendable {
    case invalidEffectCount
}

enum ExactRuntimeFactory {
    static func make(authoredEffectCount: Int) throws -> ExactRuntime {
        guard authoredEffectCount >= 0 else {
            throw ExactRuntimeFactoryError.invalidEffectCount
        }
        return ExactRuntime(authoredEffectCount: authoredEffectCount)
    }
}

enum ExactFrameError: Error, Equatable, Sendable {
    case encodingFailed
}

final class ExactProductFrameOwner {
    let runtime: ExactRuntime
    private(set) var submitCount = 0

    init(runtime: ExactRuntime) {
        self.runtime = runtime
    }

    func renderAndSubmit(failEncoding: Bool = false) throws {
        guard !failEncoding else {
            throw ExactFrameError.encodingFailed
        }
        submitCount += 1
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let effectRange = SourceRange(lower: 120, upper: 180)
let visibleRange = SourceRange(lower: 240, upper: 310)
let effectOwner = EffectScriptOwner(
    objectIndex: 0,
    effectIndex: 1,
    passIndex: 2,
    materialKey: "gain"
)

let mixed = try ScriptInventoryCompiler.compile(
    authored: [
        (
            path: "objects[0].effects[1].passes[2].constantshadervalues.gain.script",
            range: effectRange,
            source: "export function update(value) { return value + 1; }"
        ),
        (
            path: "objects[0].visible.script",
            range: visibleRange,
            source: "export function update() { return true; }"
        )
    ],
    exactOwners: [(effectRange, effectOwner)]
)
require(mixed.occurrences.count == 2, "script occurrence order changed")
require(mixed.unsupported.map(\.range) == [visibleRange], "unowned callback was not isolated")
if case .exactEffectParameter(let owner) = mixed.occurrences[0].ownership {
    require(owner == effectOwner, "exact effect owner changed")
} else {
    require(false, "effect script was not admitted by exact source ownership")
}

let mixedFactory = MockRendererFactory()
do {
    try mixedFactory.make(inventory: mixed)
    require(false, "unowned object-property callback reached renderer creation")
} catch ScriptAdmissionError.unsupported(let references) {
    require(references == [mixed.occurrences[1]], "unsupported diagnostics lost source identity")
}
require(mixedFactory.creationCount == 0, "renderer was created before SceneScript admission")

let effectOnly = try ScriptInventoryCompiler.compile(
    authored: [
        (
            path: "effect-parameter",
            range: effectRange,
            source: "export function update(value) { return value; }"
        )
    ],
    exactOwners: [(effectRange, effectOwner)]
)
let effectFactory = MockRendererFactory()
try effectFactory.make(inventory: effectOnly)
require(effectFactory.creationCount == 1, "owned effect script did not reach renderer creation")
require(effectOnly.unsupported.isEmpty, "owned effect script remained unsupported")

do {
    _ = try ScriptInventoryCompiler.compile(
        authored: [],
        exactOwners: [(effectRange, effectOwner)]
    )
    require(false, "missing exact source occurrence was accepted")
} catch ScriptAdmissionError.missingExactOccurrence(let range) {
    require(range == effectRange, "missing occurrence diagnostics changed range")
}

do {
    _ = try ScriptInventoryCompiler.compile(
        authored: [("effect", effectRange, "script")],
        exactOwners: [
            (effectRange, effectOwner),
            (effectRange, effectOwner)
        ]
    )
    require(false, "duplicate exact ownership was accepted")
} catch ScriptAdmissionError.duplicateExactOwner(let range) {
    require(range == effectRange, "duplicate-owner diagnostics changed range")
}

let noEffectRuntime = try ExactRuntimeFactory.make(authoredEffectCount: 0)
let noEffectOwner = ExactProductFrameOwner(runtime: noEffectRuntime)
try noEffectOwner.renderAndSubmit()
require(noEffectOwner.runtime.authoredEffectCount == 0, "zero-effect package changed identity")
require(noEffectOwner.submitCount == 1, "zero-effect package was not submitted by its exact owner")

let effectRuntime = try ExactRuntimeFactory.make(authoredEffectCount: 3)
let effectFrameOwner = ExactProductFrameOwner(runtime: effectRuntime)
do {
    try effectFrameOwner.renderAndSubmit(failEncoding: true)
    require(false, "failed exact frame was accepted")
} catch ExactFrameError.encodingFailed {
}
require(effectFrameOwner.submitCount == 0, "failed exact frame submitted")
try effectFrameOwner.renderAndSubmit()
require(effectFrameOwner.submitCount == 1, "successful exact frame was not submitted exactly once")

print("PASS: SceneScript admission and zero-effect product frames remain exact-only")
