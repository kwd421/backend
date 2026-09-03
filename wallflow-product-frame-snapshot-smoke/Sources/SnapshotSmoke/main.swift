import Foundation

enum PointerValidationError: Error, Equatable {
    case previous
    case current
    case state
}

struct PointerSnapshot: Equatable {
    let previous: [Double]
    let current: [Double]
    let state: [Double]

    init(previous: [Double], current: [Double], state: [Double]) throws {
        guard previous.count == 2, previous.allSatisfy(\.isFinite) else {
            throw PointerValidationError.previous
        }
        guard current.count == 2, current.allSatisfy(\.isFinite) else {
            throw PointerValidationError.current
        }
        guard state.count == 4, state.allSatisfy(\.isFinite) else {
            throw PointerValidationError.state
        }
        self.previous = previous
        self.current = current
        self.state = state
    }
}

struct ExactAudioBands: Equatable {
    let left16: [Double]
    let right16: [Double]
    let left32: [Double]
    let right32: [Double]
    let left64: [Double]
    let right64: [Double]

    init(left64: [Double], right64: [Double]) {
        precondition(left64.count == 64 && right64.count == 64)
        self.left64 = left64
        self.right64 = right64
        left32 = Self.pairwiseMaximum(left64)
        right32 = Self.pairwiseMaximum(right64)
        left16 = Self.pairwiseMaximum(left32)
        right16 = Self.pairwiseMaximum(right32)
    }

    private static func pairwiseMaximum(_ values: [Double]) -> [Double] {
        stride(from: 0, to: values.count, by: 2).map {
            max(values[$0], values[$0 + 1])
        }
    }
}

struct ProductFrameSnapshot {
    static let identity: [Double] = [
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    ]

    let modelViewProjection = identity
    let modelViewProjectionInverse = identity
    let effectTextureProjection = identity
    let effectTextureProjectionInverse = identity
    let effectModel: [Double]? = nil
    let parallax: [Double]? = nil
    let lights: [Double]? = nil
    let audio: ExactAudioBands
    let pointer: PointerSnapshot?
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let left = (0..<64).map { Double($0) / 64 }
let right = (0..<64).map { Double(63 - $0) / 64 }
let audio = ExactAudioBands(left64: left, right64: right)
require(audio.left64 == left, "64-band left channel changed")
require(audio.right64 == right, "64-band right channel changed")
require(audio.left32.count == 32 && audio.right32.count == 32, "32-band shape changed")
require(audio.left16.count == 16 && audio.right16.count == 16, "16-band shape changed")
require(audio.left32[0] == max(left[0], left[1]), "32-band reduction is not pairwise maximum")
require(audio.left16[0] == max(audio.left32[0], audio.left32[1]), "16-band reduction is not pairwise maximum")

let pointer = try PointerSnapshot(
    previous: [0.25, 0.5],
    current: [0.75, 1],
    state: [1, 0, 0, 0]
)
let frame = ProductFrameSnapshot(audio: audio, pointer: pointer)
require(frame.modelViewProjection == ProductFrameSnapshot.identity, "MVP is not explicit identity")
require(frame.effectTextureProjectionInverse == ProductFrameSnapshot.identity, "texture projection inverse is not explicit identity")
require(frame.effectModel == nil, "unrecovered effect-model state was invented")
require(frame.parallax == nil, "unrecovered parallax state was invented")
require(frame.lights == nil, "unrecovered light state was invented")
require(frame.pointer == pointer, "validated pointer state changed")

do {
    _ = try PointerSnapshot(previous: [0], current: [0, 0], state: [0, 0, 0, 0])
    require(false, "incomplete previous pointer position was accepted")
} catch PointerValidationError.previous {
} catch {
    require(false, "unexpected previous-position error: \(error)")
}

do {
    _ = try PointerSnapshot(previous: [0, 0], current: [.nan, 0], state: [0, 0, 0, 0])
    require(false, "non-finite current pointer position was accepted")
} catch PointerValidationError.current {
} catch {
    require(false, "unexpected current-position error: \(error)")
}

print("PASS: exact product-frame snapshot invariants")
