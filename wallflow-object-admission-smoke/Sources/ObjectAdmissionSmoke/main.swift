import Foundation

private struct SourceObject: Equatable, Sendable {
    let objectIndex: Int
    let objectID: Int?
    let name: String?
    let hasImage: Bool
    let hasSound: Bool
    let remainingFields: [String]
}

private struct ProductLayer: Equatable, Sendable {
    let layerIndex: Int
    let objectID: Int?
    let name: String
}

private struct Ownership: Equatable, Sendable {
    let objectIndex: Int
    let objectID: Int
    let layerIndex: Int
}

private enum AdmissionError: Error, Equatable, Sendable {
    case mixedImageAndSound(objectIndex: Int)
    case unsupportedObject(objectIndex: Int, fields: [String])
    case sourceImageMissingID(objectIndex: Int)
    case duplicateSourceID(Int)
    case productLayerMissingID(layerIndex: Int)
    case duplicateProductID(Int)
    case foreignProductLayer(layerIndex: Int, objectID: Int)
    case droppedSourceImage(objectIndex: Int, objectID: Int)
}

private enum ObjectAdmission {
    static func resolve(
        source: [SourceObject],
        product: [ProductLayer]
    ) throws -> [Ownership] {
        var sourceByID: [Int: SourceObject] = [:]
        var sourceOrder: [Int] = []
        for object in source {
            if object.hasImage && object.hasSound {
                throw AdmissionError.mixedImageAndSound(
                    objectIndex: object.objectIndex
                )
            }
            if object.hasSound {
                continue
            }
            guard object.hasImage else {
                throw AdmissionError.unsupportedObject(
                    objectIndex: object.objectIndex,
                    fields: object.remainingFields
                )
            }
            guard let objectID = object.objectID else {
                throw AdmissionError.sourceImageMissingID(
                    objectIndex: object.objectIndex
                )
            }
            guard sourceByID.updateValue(object, forKey: objectID) == nil else {
                throw AdmissionError.duplicateSourceID(objectID)
            }
            sourceOrder.append(objectID)
        }

        var productIndexByID: [Int: Int] = [:]
        for layer in product {
            guard let objectID = layer.objectID else {
                throw AdmissionError.productLayerMissingID(
                    layerIndex: layer.layerIndex
                )
            }
            guard productIndexByID.updateValue(
                layer.layerIndex,
                forKey: objectID
            ) == nil else {
                throw AdmissionError.duplicateProductID(objectID)
            }
            guard sourceByID[objectID] != nil else {
                throw AdmissionError.foreignProductLayer(
                    layerIndex: layer.layerIndex,
                    objectID: objectID
                )
            }
        }

        return try sourceOrder.map { objectID in
            guard let object = sourceByID[objectID] else {
                preconditionFailure("source object order lost id owner")
            }
            guard let layerIndex = productIndexByID[objectID] else {
                throw AdmissionError.droppedSourceImage(
                    objectIndex: object.objectIndex,
                    objectID: objectID
                )
            }
            return Ownership(
                objectIndex: object.objectIndex,
                objectID: objectID,
                layerIndex: layerIndex
            )
        }
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

let source = [
    SourceObject(
        objectIndex: 0,
        objectID: 20,
        name: "back",
        hasImage: true,
        hasSound: false,
        remainingFields: ["origin", "size"]
    ),
    SourceObject(
        objectIndex: 1,
        objectID: 10,
        name: "front",
        hasImage: true,
        hasSound: false,
        remainingFields: ["origin", "size"]
    )
]
let product = [
    ProductLayer(layerIndex: 0, objectID: 10, name: "front"),
    ProductLayer(layerIndex: 1, objectID: 20, name: "back")
]
let ownership = try ObjectAdmission.resolve(source: source, product: product)
require(ownership == [
    Ownership(objectIndex: 0, objectID: 20, layerIndex: 1),
    Ownership(objectIndex: 1, objectID: 10, layerIndex: 0)
], "authored source order or id join changed")

do {
    _ = try ObjectAdmission.resolve(
        source: source,
        product: [product[1]]
    )
    require(false, "dropped source ImageLayer was accepted")
} catch AdmissionError.droppedSourceImage(let index, let id) {
    require(index == 1 && id == 10, "dropped-layer diagnostics changed")
}

do {
    _ = try ObjectAdmission.resolve(
        source: source,
        product: product + [
            ProductLayer(layerIndex: 2, objectID: 99, name: "foreign")
        ]
    )
    require(false, "foreign product layer was accepted")
} catch AdmissionError.foreignProductLayer(let index, let id) {
    require(index == 2 && id == 99, "foreign-layer diagnostics changed")
}

do {
    _ = try ObjectAdmission.resolve(
        source: [
            SourceObject(
                objectIndex: 0,
                objectID: nil,
                name: "anonymous",
                hasImage: true,
                hasSound: false,
                remainingFields: []
            )
        ],
        product: []
    )
    require(false, "anonymous image object was joined positionally")
} catch AdmissionError.sourceImageMissingID(let index) {
    require(index == 0, "anonymous-image diagnostics changed")
}

do {
    _ = try ObjectAdmission.resolve(
        source: [
            SourceObject(
                objectIndex: 0,
                objectID: 5,
                name: "snow",
                hasImage: false,
                hasSound: false,
                remainingFields: ["particle", "visible"]
            )
        ],
        product: []
    )
    require(false, "unclassified source object was discarded")
} catch AdmissionError.unsupportedObject(let index, let fields) {
    require(index == 0, "unsupported-object index changed")
    require(fields == ["particle", "visible"], "unsupported fields changed")
}

do {
    _ = try ObjectAdmission.resolve(
        source: [
            SourceObject(
                objectIndex: 0,
                objectID: 7,
                name: "mixed",
                hasImage: true,
                hasSound: true,
                remainingFields: []
            )
        ],
        product: []
    )
    require(false, "mixed image/sound owner was accepted")
} catch AdmissionError.mixedImageAndSound(let index) {
    require(index == 0, "mixed-owner diagnostics changed")
}

print("PASS: every authored WPE object has one exact product owner")
