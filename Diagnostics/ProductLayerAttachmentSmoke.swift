import Foundation

struct Effect: Equatable {
    let objectIndex: Int
    let effectIndex: Int
    let objectID: Int?
}

enum ProductPayload: Equatable {
    case archiveBackedImage
    case generated
}

struct ProductLayer {
    let drawOrder: Int
    let objectID: Int?
    let payload: ProductPayload
}

enum AttachmentError: Error, Equatable {
    case inconsistentAuthoredObjectID(objectIndex: Int)
    case missingProductImageLayer(objectIndex: Int, objectID: Int?)
    case ambiguousProductImageLayer(
        objectIndex: Int,
        objectID: Int?,
        productLayerIndices: [Int]
    )
}

struct Attachment: Equatable {
    let productLayerIndex: Int
    let authoredObjectIndex: Int
    let objectID: Int?
    let effects: [Effect]
}

func attach(
    effects: [Effect],
    productLayers: [ProductLayer]
) throws -> [Attachment] {
    let effectsByObjectIndex = Dictionary(
        grouping: effects,
        by: { $0.objectIndex }
    )
    return try effectsByObjectIndex.keys.sorted().map { objectIndex in
        let effects = (effectsByObjectIndex[objectIndex] ?? []).sorted {
            $0.effectIndex < $1.effectIndex
        }
        let authoredObjectIDs = Set(effects.map(\.objectID))
        guard authoredObjectIDs.count == 1 else {
            throw AttachmentError.inconsistentAuthoredObjectID(
                objectIndex: objectIndex
            )
        }
        let objectID = authoredObjectIDs.first ?? nil
        let productLayerIndices: [Int] = productLayers.enumerated().compactMap { entry -> Int? in
            let (index, layer) = entry
            guard layer.drawOrder == objectIndex,
                  layer.payload == .archiveBackedImage,
                  layer.objectID == objectID else {
                return nil
            }
            return index
        }
        guard let productLayerIndex = productLayerIndices.first else {
            throw AttachmentError.missingProductImageLayer(
                objectIndex: objectIndex,
                objectID: objectID
            )
        }
        guard productLayerIndices.count == 1 else {
            throw AttachmentError.ambiguousProductImageLayer(
                objectIndex: objectIndex,
                objectID: objectID,
                productLayerIndices: productLayerIndices
            )
        }
        return Attachment(
            productLayerIndex: productLayerIndex,
            authoredObjectIndex: objectIndex,
            objectID: objectID,
            effects: effects
        )
    }
}

func expectAttachmentError(
    _ expected: AttachmentError,
    operation: () throws -> Void
) {
    do {
        try operation()
        preconditionFailure("Expected attachment failure: \(expected)")
    } catch let actual as AttachmentError {
        precondition(actual == expected, "Unexpected attachment failure: \(actual)")
    } catch {
        preconditionFailure("Unexpected non-attachment failure: \(error)")
    }
}

@main
struct Main {
    static func main() throws {
        let effects = [
            Effect(objectIndex: 3, effectIndex: 1, objectID: 9),
            Effect(objectIndex: 3, effectIndex: 0, objectID: 9)
        ]
        let productLayers = [
            ProductLayer(drawOrder: 3, objectID: nil, payload: .generated),
            ProductLayer(drawOrder: 3, objectID: 9, payload: .archiveBackedImage)
        ]
        let attachments = try attach(
            effects: effects,
            productLayers: productLayers
        )
        precondition(attachments == [Attachment(
            productLayerIndex: 1,
            authoredObjectIndex: 3,
            objectID: 9,
            effects: effects.sorted { $0.effectIndex < $1.effectIndex }
        )])

        expectAttachmentError(
            .missingProductImageLayer(objectIndex: 3, objectID: 9)
        ) {
            _ = try attach(
                effects: effects,
                productLayers: [
                    ProductLayer(
                        drawOrder: 3,
                        objectID: 10,
                        payload: .archiveBackedImage
                    )
                ]
            )
        }

        expectAttachmentError(
            .ambiguousProductImageLayer(
                objectIndex: 3,
                objectID: 9,
                productLayerIndices: [0, 1]
            )
        ) {
            _ = try attach(
                effects: effects,
                productLayers: [
                    ProductLayer(
                        drawOrder: 3,
                        objectID: 9,
                        payload: .archiveBackedImage
                    ),
                    ProductLayer(
                        drawOrder: 3,
                        objectID: 9,
                        payload: .archiveBackedImage
                    )
                ]
            )
        }

        print("authored product-layer attachment invariant OK")
    }
}
