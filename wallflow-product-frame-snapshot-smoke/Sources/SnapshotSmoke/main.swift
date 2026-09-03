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
    let exactAudio: ExactAudioBands?
    let pointer: PointerSnapshot?
}

enum StaticClearAdmissionError: Error, Equatable {
    case missingClearEnabled
    case unclearedBackbufferUnsupported
    case missingClearColor
    case invalidClearColor
}

struct StaticClearProgram: Equatable {
    let clearEnabled: Bool?
    let clearColor: [Double]?
}

struct StaticClearColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
}

enum StaticClearAdmission {
    static func resolve(
        program: StaticClearProgram,
        exactBackend: Bool,
        fallback: StaticClearColor
    ) throws -> StaticClearColor {
        do {
            guard let clearEnabled = program.clearEnabled else {
                throw StaticClearAdmissionError.missingClearEnabled
            }
            guard clearEnabled else {
                throw StaticClearAdmissionError.unclearedBackbufferUnsupported
            }
            guard let components = program.clearColor else {
                throw StaticClearAdmissionError.missingClearColor
            }
            guard components.count == 3,
                  components.allSatisfy(\.isFinite) else {
                throw StaticClearAdmissionError.invalidClearColor
            }
            return StaticClearColor(
                red: components[0],
                green: components[1],
                blue: components[2]
            )
        } catch {
            if exactBackend {
                throw error
            }
            return fallback
        }
    }
}

enum MockFrameError: Error {
    case exactEncodingFailed
}

final class MockProductFrameOwner {
    var clock = 0
    var exactCalls = 0
    var legacyCalls = 0
    var submitCalls = 0

    func render(exactAvailable: Bool, failExact: Bool) throws {
        if exactAvailable {
            exactCalls += 1
            let previousClock = clock
            clock += 1
            do {
                if failExact {
                    throw MockFrameError.exactEncodingFailed
                }
                submitCalls += 1
            } catch {
                clock = previousClock
                throw error
            }
            return
        }
        legacyCalls += 1
        submitCalls += 1
    }
}

final class MockDrawableOwner {
    private(set) var acquisitionCount = 0

    func beginFrame(
        exactBackend: Bool,
        program: StaticClearProgram,
        fallback: StaticClearColor
    ) throws -> StaticClearColor {
        let color = try StaticClearAdmission.resolve(
            program: program,
            exactBackend: exactBackend,
            fallback: fallback
        )
        acquisitionCount += 1
        return color
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let pointer = try PointerSnapshot(
    previous: [0.25, 0.5],
    current: [0.75, 1],
    state: [1, 0, 0, 0]
)
let unavailableAudioFrame = ProductFrameSnapshot(
    exactAudio: nil,
    pointer: pointer
)
require(unavailableAudioFrame.exactAudio == nil, "unavailable exact audio was replaced by silence")
require(unavailableAudioFrame.modelViewProjection == ProductFrameSnapshot.identity, "MVP is not explicit identity")
require(unavailableAudioFrame.effectTextureProjectionInverse == ProductFrameSnapshot.identity, "texture projection inverse is not explicit identity")
require(unavailableAudioFrame.effectModel == nil, "unrecovered effect-model state was invented")
require(unavailableAudioFrame.parallax == nil, "unrecovered parallax state was invented")
require(unavailableAudioFrame.lights == nil, "unrecovered light state was invented")
require(unavailableAudioFrame.pointer == pointer, "validated pointer state changed")

let left = (0..<64).map { Double($0) / 64 }
let right = (0..<64).map { Double(63 - $0) / 64 }
let audio = ExactAudioBands(left64: left, right64: right)
let publishedAudioFrame = ProductFrameSnapshot(
    exactAudio: audio,
    pointer: nil
)
require(publishedAudioFrame.exactAudio?.left64 == left, "64-band left channel changed")
require(publishedAudioFrame.exactAudio?.right64 == right, "64-band right channel changed")
require(publishedAudioFrame.exactAudio?.left32.count == 32, "32-band shape changed")
require(publishedAudioFrame.exactAudio?.left16.count == 16, "16-band shape changed")
require(publishedAudioFrame.exactAudio?.left32[0] == max(left[0], left[1]), "32-band reduction is not pairwise maximum")

let owner = MockProductFrameOwner()
do {
    try owner.render(exactAvailable: true, failExact: true)
    require(false, "failing exact frame was accepted")
} catch MockFrameError.exactEncodingFailed {
}
require(owner.clock == 0, "failed exact frame advanced the clock")
require(owner.exactCalls == 1, "exact frame was not attempted once")
require(owner.legacyCalls == 0, "exact failure silently invoked legacy rendering")
require(owner.submitCalls == 0, "failed exact frame submitted a command buffer")

try owner.render(exactAvailable: true, failExact: false)
require(owner.clock == 1, "successful exact frame did not retain its clock state")
require(owner.submitCalls == 1, "successful exact frame did not submit exactly once")
require(owner.legacyCalls == 0, "successful exact frame invoked legacy rendering")

try owner.render(exactAvailable: false, failExact: false)
require(owner.legacyCalls == 1, "legacy rendering was not selected when exact runtime was absent")
require(owner.submitCalls == 2, "legacy frame did not submit exactly once")

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

let fallbackClear = StaticClearColor(red: 0.10, green: 0.10, blue: 0.15)
let authoredClear = StaticClearProgram(
    clearEnabled: true,
    clearColor: [0.7, 0.2, 1.25]
)
let exactDrawable = MockDrawableOwner()
let exactClear = try exactDrawable.beginFrame(
    exactBackend: true,
    program: authoredClear,
    fallback: fallbackClear
)
require(exactClear == StaticClearColor(red: 0.7, green: 0.2, blue: 1.25), "authored clear color changed")
require(exactDrawable.acquisitionCount == 1, "supported exact clear did not acquire one drawable")

let unsupportedExactDrawable = MockDrawableOwner()
do {
    _ = try unsupportedExactDrawable.beginFrame(
        exactBackend: true,
        program: StaticClearProgram(
            clearEnabled: false,
            clearColor: [0.7, 0.2, 1.25]
        ),
        fallback: fallbackClear
    )
    require(false, "uncleared exact backbuffer was approximated")
} catch StaticClearAdmissionError.unclearedBackbufferUnsupported {
}
require(unsupportedExactDrawable.acquisitionCount == 0, "failed exact clear acquired a drawable")

let missingExactDrawable = MockDrawableOwner()
do {
    _ = try missingExactDrawable.beginFrame(
        exactBackend: true,
        program: StaticClearProgram(
            clearEnabled: nil,
            clearColor: [0.7, 0.2, 1.25]
        ),
        fallback: fallbackClear
    )
    require(false, "missing exact clear default was invented")
} catch StaticClearAdmissionError.missingClearEnabled {
}
require(missingExactDrawable.acquisitionCount == 0, "missing exact clear acquired a drawable")

let legacyDrawable = MockDrawableOwner()
let legacyClear = try legacyDrawable.beginFrame(
    exactBackend: false,
    program: StaticClearProgram(
        clearEnabled: false,
        clearColor: nil
    ),
    fallback: fallbackClear
)
require(legacyClear == fallbackClear, "legacy compatibility fallback changed")
require(legacyDrawable.acquisitionCount == 1, "legacy fallback did not acquire one drawable")

print("PASS: exact product-frame ownership, snapshot, and clear admission invariants")
