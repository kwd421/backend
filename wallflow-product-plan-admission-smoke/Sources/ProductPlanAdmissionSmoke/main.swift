import Foundation

private enum Texture: Equatable, Sendable {
    case encoded(Data)
    case rgba(width: Int, height: Int, bytes: Data)
    case procedural
}

private struct Layer: Equatable, Sendable {
    let objectID: Int
    var origin: (Double, Double)
    var size: (Double, Double)
    var scale: (Double, Double)
    var rotation: Double
    var alpha: Double
    var primary: Texture
    var auxiliary: [String: Texture]
}

private enum AdmissionError: Error, Equatable, Sendable {
    case procedural(key: String?)
    case invalidOrigin(Double, Double)
    case invalidSize(Double, Double)
    case invalidScale(Double, Double)
    case invalidRotation(Double)
    case invalidAlpha(Double)
    case invalidExtent(key: String?, width: Int, height: Int)
    case invalidByteCount(
        key: String?,
        width: Int,
        height: Int,
        expected: Int?,
        actual: Int
    )
}

private enum ProductPlanAdmission {
    static func validate(_ layer: Layer) throws {
        guard layer.origin.0.isFinite, layer.origin.1.isFinite else {
            throw AdmissionError.invalidOrigin(layer.origin.0, layer.origin.1)
        }
        guard layer.size.0.isFinite,
              layer.size.1.isFinite,
              layer.size.0 > 0,
              layer.size.1 > 0 else {
            throw AdmissionError.invalidSize(layer.size.0, layer.size.1)
        }
        guard layer.scale.0.isFinite, layer.scale.1.isFinite else {
            throw AdmissionError.invalidScale(layer.scale.0, layer.scale.1)
        }
        guard layer.rotation.isFinite else {
            throw AdmissionError.invalidRotation(layer.rotation)
        }
        guard layer.alpha.isFinite,
              layer.alpha >= 0,
              layer.alpha <= 1 else {
            throw AdmissionError.invalidAlpha(layer.alpha)
        }

        try validateTexture(layer.primary, key: nil)
        for key in layer.auxiliary.keys.sorted() {
            guard let texture = layer.auxiliary[key] else { continue }
            try validateTexture(texture, key: key)
        }
    }

    private static func validateTexture(
        _ texture: Texture,
        key: String?
    ) throws {
        switch texture {
        case .encoded:
            return
        case .procedural:
            throw AdmissionError.procedural(key: key)
        case .rgba(let width, let height, let bytes):
            guard width > 0, height > 0 else {
                throw AdmissionError.invalidExtent(
                    key: key,
                    width: width,
                    height: height
                )
            }
            let pixelCount = width.multipliedReportingOverflow(by: height)
            let byteCount = pixelCount.partialValue.multipliedReportingOverflow(by: 4)
            let expected = pixelCount.overflow || byteCount.overflow
                ? nil
                : byteCount.partialValue
            guard let expected, bytes.count == expected else {
                throw AdmissionError.invalidByteCount(
                    key: key,
                    width: width,
                    height: height,
                    expected: expected,
                    actual: bytes.count
                )
            }
        }
    }
}

private func validLayer() -> Layer {
    Layer(
        objectID: 9,
        origin: (2, 2),
        size: (4, 4),
        scale: (1, 1),
        rotation: 0,
        alpha: 1,
        primary: .rgba(
            width: 1,
            height: 1,
            bytes: Data([255, 255, 255, 255])
        ),
        auxiliary: [:]
    )
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

try ProductPlanAdmission.validate(validLayer())

var invalidOrigin = validLayer()
invalidOrigin.origin = (.infinity, 2)
do {
    try ProductPlanAdmission.validate(invalidOrigin)
    require(false, "non-finite origin was accepted")
} catch AdmissionError.invalidOrigin(let x, let y) {
    require(x == .infinity && y == 2, "origin diagnostics changed")
}

var invalidSize = validLayer()
invalidSize.size = (0, 4)
do {
    try ProductPlanAdmission.validate(invalidSize)
    require(false, "zero width was accepted")
} catch AdmissionError.invalidSize(let width, let height) {
    require(width == 0 && height == 4, "size diagnostics changed")
}

var invalidScale = validLayer()
invalidScale.scale = (1, -.infinity)
do {
    try ProductPlanAdmission.validate(invalidScale)
    require(false, "non-finite scale was accepted")
} catch AdmissionError.invalidScale(let x, let y) {
    require(x == 1 && y == -.infinity, "scale diagnostics changed")
}

var invalidRotation = validLayer()
invalidRotation.rotation = .infinity
do {
    try ProductPlanAdmission.validate(invalidRotation)
    require(false, "non-finite rotation was accepted")
} catch AdmissionError.invalidRotation(let value) {
    require(value == .infinity, "rotation diagnostics changed")
}

var invalidAlpha = validLayer()
invalidAlpha.alpha = 1.01
do {
    try ProductPlanAdmission.validate(invalidAlpha)
    require(false, "out-of-range alpha was accepted")
} catch AdmissionError.invalidAlpha(let value) {
    require(value == 1.01, "alpha diagnostics changed")
}

var invalidExtent = validLayer()
invalidExtent.primary = .rgba(width: 0, height: 1, bytes: Data())
do {
    try ProductPlanAdmission.validate(invalidExtent)
    require(false, "zero RGBA extent was accepted")
} catch AdmissionError.invalidExtent(let key, let width, let height) {
    require(key == nil && width == 0 && height == 1, "extent diagnostics changed")
}

var wrongBytes = validLayer()
wrongBytes.primary = .rgba(
    width: 2,
    height: 2,
    bytes: Data(repeating: 255, count: 15)
)
do {
    try ProductPlanAdmission.validate(wrongBytes)
    require(false, "short RGBA payload was accepted")
} catch AdmissionError.invalidByteCount(
    let key,
    let width,
    let height,
    let expected,
    let actual
) {
    require(key == nil, "primary key diagnostics changed")
    require(width == 2 && height == 2, "byte-count extent changed")
    require(expected == 16 && actual == 15, "byte-count diagnostics changed")
}

var overflow = validLayer()
overflow.primary = .rgba(width: Int.max, height: 2, bytes: Data())
do {
    try ProductPlanAdmission.validate(overflow)
    require(false, "overflowing RGBA size was accepted")
} catch AdmissionError.invalidByteCount(
    let key,
    let width,
    let height,
    let expected,
    let actual
) {
    require(key == nil, "overflow primary key changed")
    require(width == Int.max && height == 2, "overflow extent changed")
    require(expected == nil && actual == 0, "overflow diagnostics changed")
}

var auxiliary = validLayer()
auxiliary.auxiliary = [
    "z-valid": .encoded(Data([1])),
    "a-mask": .rgba(
        width: 2,
        height: 1,
        bytes: Data(repeating: 0, count: 7)
    )
]
do {
    try ProductPlanAdmission.validate(auxiliary)
    require(false, "invalid auxiliary RGBA payload was accepted")
} catch AdmissionError.invalidByteCount(
    let key,
    _,
    _,
    let expected,
    let actual
) {
    require(key == "a-mask", "auxiliary key ordering changed")
    require(expected == 8 && actual == 7, "auxiliary byte diagnostics changed")
}

var procedural = validLayer()
procedural.auxiliary = ["mask": .procedural]
do {
    try ProductPlanAdmission.validate(procedural)
    require(false, "procedural auxiliary texture was accepted")
} catch AdmissionError.procedural(let key) {
    require(key == "mask", "procedural auxiliary key changed")
}

print("PASS: product geometry and RGBA payloads fail before runtime creation")
