import Foundation

private struct EffectReference: Hashable, Sendable {
    let objectIndex: Int
    let effectIndex: Int
}

private struct EffectIdentity: Equatable, Sendable {
    let runtimeProgramIndex: Int
    let reference: EffectReference
    let objectID: Int?
}

private enum BindingError: Error, Equatable {
    case missingObjectID(EffectReference)
    case duplicateReference(EffectReference)
    case duplicateLayerObjectID(objectID: Int, first: Int, duplicate: Int)
    case missingLayer(objectID: Int, reference: EffectReference)
}

private struct BindingPlan: Equatable, Sendable {
    struct Layer: Equatable, Sendable {
        let layerIndex: Int
        let objectID: Int
        let runtimeProgramIndices: [Int]
    }

    let layers: [Layer]

    init(layerObjectIDs: [Int?], effects: [EffectIdentity]) throws {
        var layerByObjectID: [Int: Int] = [:]
        for (index, objectID) in layerObjectIDs.enumerated() {
            guard let objectID else { continue }
            if let first = layerByObjectID[objectID] {
                throw BindingError.duplicateLayerObjectID(
                    objectID: objectID,
                    first: first,
                    duplicate: index
                )
            }
            layerByObjectID[objectID] = index
        }

        var seen: Set<EffectReference> = []
        var indicesByLayer: [Int: [Int]] = [:]
        var objectIDByLayer: [Int: Int] = [:]
        for effect in effects {
            guard seen.insert(effect.reference).inserted else {
                throw BindingError.duplicateReference(effect.reference)
            }
            guard let objectID = effect.objectID else {
                throw BindingError.missingObjectID(effect.reference)
            }
            guard let layerIndex = layerByObjectID[objectID] else {
                throw BindingError.missingLayer(objectID: objectID, reference: effect.reference)
            }
            objectIDByLayer[layerIndex] = objectID
            indicesByLayer[layerIndex, default: []].append(effect.runtimeProgramIndex)
        }

        layers = indicesByLayer.keys.sorted().map { layerIndex in
            Layer(
                layerIndex: layerIndex,
                objectID: objectIDByLayer[layerIndex]!,
                runtimeProgramIndices: indicesByLayer[layerIndex]!
            )
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) -> Never? {
    guard !condition() else { return nil }
    fputs("BINDING_SMOKE_FAILED: \(message)\n", stderr)
    exit(EXIT_FAILURE)
}

let plan = try BindingPlan(
    layerObjectIDs: [40, nil, 20],
    effects: [
        EffectIdentity(
            runtimeProgramIndex: 0,
            reference: EffectReference(objectIndex: 1, effectIndex: 0),
            objectID: 20
        ),
        EffectIdentity(
            runtimeProgramIndex: 1,
            reference: EffectReference(objectIndex: 1, effectIndex: 1),
            objectID: 20
        ),
        EffectIdentity(
            runtimeProgramIndex: 2,
            reference: EffectReference(objectIndex: 4, effectIndex: 0),
            objectID: 40
        )
    ]
)
_ = require(plan.layers == [
    BindingPlan.Layer(layerIndex: 0, objectID: 40, runtimeProgramIndices: [2]),
    BindingPlan.Layer(layerIndex: 2, objectID: 20, runtimeProgramIndices: [0, 1])
], "authored effect order or product layer order changed")

do {
    _ = try BindingPlan(
        layerObjectIDs: [7, 7],
        effects: []
    )
    _ = require(false, "duplicate product object ids were accepted")
} catch let error as BindingError {
    _ = require(error == .duplicateLayerObjectID(objectID: 7, first: 0, duplicate: 1), "wrong duplicate-layer error")
}

do {
    let reference = EffectReference(objectIndex: 3, effectIndex: 2)
    _ = try BindingPlan(
        layerObjectIDs: [30],
        effects: [EffectIdentity(runtimeProgramIndex: 0, reference: reference, objectID: nil)]
    )
    _ = require(false, "an exact effect without object identity was accepted")
} catch let error as BindingError {
    _ = require(error == .missingObjectID(EffectReference(objectIndex: 3, effectIndex: 2)), "wrong missing-id error")
}

print("WALLFLOW_BINDING_SMOKE_OK")
