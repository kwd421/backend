import Foundation

private struct AdmittedLayer: Equatable, Sendable {
    let authoredObjectIndex: Int
    let objectID: Int
    let productLayerIndex: Int
}

private struct EffectAttachment: Equatable, Sendable {
    let authoredObjectIndex: Int
    let productLayerIndex: Int
}

private enum AttachmentAdmissionError: Error, Equatable, Sendable {
    case ownershipMismatch(
        authoredObjectIndex: Int,
        attachedProductLayerIndex: Int,
        admittedProductLayerIndex: Int?
    )
}

private final class RuntimeResourceFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func create() {
        lock.withLock { count += 1 }
    }

    var creationCount: Int {
        lock.withLock { count }
    }
}

private enum AttachmentAdmission {
    static func createRuntime(
        admitted: [AdmittedLayer],
        attachments: [EffectAttachment],
        resourceFactory: RuntimeResourceFactory
    ) throws {
        let admittedProductIndexByObjectIndex = Dictionary(
            uniqueKeysWithValues: admitted.map {
                ($0.authoredObjectIndex, $0.productLayerIndex)
            }
        )
        for attachment in attachments {
            let admittedProductLayerIndex = admittedProductIndexByObjectIndex[
                attachment.authoredObjectIndex
            ]
            guard admittedProductLayerIndex == attachment.productLayerIndex else {
                throw AttachmentAdmissionError.ownershipMismatch(
                    authoredObjectIndex: attachment.authoredObjectIndex,
                    attachedProductLayerIndex: attachment.productLayerIndex,
                    admittedProductLayerIndex: admittedProductLayerIndex
                )
            }
        }
        resourceFactory.create()
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

let admitted = [
    AdmittedLayer(
        authoredObjectIndex: 0,
        objectID: 9,
        productLayerIndex: 0
    )
]

let matchingFactory = RuntimeResourceFactory()
try AttachmentAdmission.createRuntime(
    admitted: admitted,
    attachments: [
        EffectAttachment(
            authoredObjectIndex: 0,
            productLayerIndex: 0
        )
    ],
    resourceFactory: matchingFactory
)
require(
    matchingFactory.creationCount == 1,
    "matching attachment did not create runtime resources exactly once"
)

let mismatchedFactory = RuntimeResourceFactory()
do {
    try AttachmentAdmission.createRuntime(
        admitted: admitted,
        attachments: [
            EffectAttachment(
                authoredObjectIndex: 0,
                productLayerIndex: 1
            )
        ],
        resourceFactory: mismatchedFactory
    )
    require(false, "mismatched attachment reached runtime creation")
} catch AttachmentAdmissionError.ownershipMismatch(
    let objectIndex,
    let attachedIndex,
    let admittedIndex
) {
    require(objectIndex == 0, "mismatch object coordinate changed")
    require(attachedIndex == 1, "mismatch attachment coordinate changed")
    require(admittedIndex == 0, "mismatch admitted coordinate changed")
}
require(
    mismatchedFactory.creationCount == 0,
    "mismatched attachment created runtime resources"
)

let unownedFactory = RuntimeResourceFactory()
do {
    try AttachmentAdmission.createRuntime(
        admitted: admitted,
        attachments: [
            EffectAttachment(
                authoredObjectIndex: 4,
                productLayerIndex: 0
            )
        ],
        resourceFactory: unownedFactory
    )
    require(false, "attachment without an admitted source owner was accepted")
} catch AttachmentAdmissionError.ownershipMismatch(
    let objectIndex,
    let attachedIndex,
    let admittedIndex
) {
    require(objectIndex == 4, "unowned object coordinate changed")
    require(attachedIndex == 0, "unowned attachment coordinate changed")
    require(admittedIndex == nil, "unowned attachment gained an admitted owner")
}
require(
    unownedFactory.creationCount == 0,
    "unowned attachment created runtime resources"
)

print("PASS: effect attachments must reproduce immutable package ownership")
