import Foundation
import Metal

enum ChainSmokeError: Error, Equatable {
    case noDevice
    case textureAllocationFailed
    case emptyEffectChain
    case aliasedTextures
    case incompatibleSize
    case incompatiblePixelFormat(input: UInt, output: UInt)
    case unsupportedTexture(
        name: String,
        textureType: UInt,
        arrayLength: Int,
        sampleCount: Int
    )
    case missingUsage(name: String, actual: UInt, required: UInt)
    case escapedPair(effectID: String)
}

struct Effect {
    let id: String
}

struct EffectResult {
    let output: MTLTexture
    let opposite: MTLTexture
}

struct EffectRequest {
    let effect: Effect
    let input: MTLTexture
    let output: MTLTexture
}

struct ChainResult {
    let output: MTLTexture
    let opposite: MTLTexture
    let count: Int
}

func renderChain(
    effects: [Effect],
    input originalInput: MTLTexture,
    output originalOutput: MTLTexture,
    render: (EffectRequest) throws -> EffectResult
) throws -> ChainResult {
    guard !effects.isEmpty else {
        throw ChainSmokeError.emptyEffectChain
    }
    try validatePair(input: originalInput, output: originalOutput)

    var input = originalInput
    var output = originalOutput
    for effect in effects {
        let result = try render(EffectRequest(
            effect: effect,
            input: input,
            output: output
        ))
        let isPermutation = (result.output === input && result.opposite === output)
            || (result.output === output && result.opposite === input)
        guard isPermutation else {
            throw ChainSmokeError.escapedPair(effectID: effect.id)
        }
        input = result.output
        output = result.opposite
    }
    return ChainResult(output: input, opposite: output, count: effects.count)
}

func validatePair(input: MTLTexture, output: MTLTexture) throws {
    guard input !== output else {
        throw ChainSmokeError.aliasedTextures
    }
    guard input.width == output.width,
          input.height == output.height else {
        throw ChainSmokeError.incompatibleSize
    }
    guard input.pixelFormat == output.pixelFormat else {
        throw ChainSmokeError.incompatiblePixelFormat(
            input: input.pixelFormat.rawValue,
            output: output.pixelFormat.rawValue
        )
    }
    try validateTexture(input, name: "input")
    try validateTexture(output, name: "output")
}

func validateTexture(_ texture: MTLTexture, name: String) throws {
    guard texture.textureType == .type2D,
          texture.arrayLength == 1,
          texture.sampleCount == 1 else {
        throw ChainSmokeError.unsupportedTexture(
            name: name,
            textureType: texture.textureType.rawValue,
            arrayLength: texture.arrayLength,
            sampleCount: texture.sampleCount
        )
    }
    let required: MTLTextureUsage = [.shaderRead, .renderTarget]
    guard texture.usage.rawValue & required.rawValue == required.rawValue else {
        throw ChainSmokeError.missingUsage(
            name: name,
            actual: texture.usage.rawValue,
            required: required.rawValue
        )
    }
}

func makeTexture(
    device: MTLDevice,
    width: Int = 4,
    height: Int = 4,
    usage: MTLTextureUsage = [.shaderRead, .renderTarget]
) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: width,
        height: height,
        mipmapped: false
    )
    descriptor.usage = usage
    descriptor.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: descriptor) else {
        throw ChainSmokeError.textureAllocationFailed
    }
    return texture
}

func requireChainError(
    _ expected: ChainSmokeError,
    operation: () throws -> Void
) {
    do {
        try operation()
        preconditionFailure("Expected \(expected)")
    } catch let actual as ChainSmokeError {
        precondition(actual == expected, "Expected \(expected), got \(actual)")
    } catch {
        preconditionFailure("Unexpected error \(error)")
    }
}

@main
struct Main {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ChainSmokeError.noDevice
        }
        let input = try makeTexture(device: device)
        let output = try makeTexture(device: device)
        let effects = [Effect(id: "first"), Effect(id: "second")]
        var calls: [(String, MTLTexture, MTLTexture)] = []

        let result = try renderChain(
            effects: effects,
            input: input,
            output: output
        ) { request in
            calls.append((request.effect.id, request.input, request.output))
            return EffectResult(
                output: request.output,
                opposite: request.input
            )
        }

        precondition(calls.count == 2)
        precondition(calls[0].0 == "first")
        precondition(calls[0].1 === input)
        precondition(calls[0].2 === output)
        precondition(calls[1].0 == "second")
        precondition(calls[1].1 === output)
        precondition(calls[1].2 === input)
        precondition(result.output === input)
        precondition(result.opposite === output)
        precondition(result.count == 2)

        requireChainError(.aliasedTextures) {
            _ = try renderChain(
                effects: effects,
                input: input,
                output: input,
                render: { request in
                    EffectResult(
                        output: request.output,
                        opposite: request.input
                    )
                }
            )
        }

        let escaped = try makeTexture(device: device)
        requireChainError(.escapedPair(effectID: "first")) {
            _ = try renderChain(
                effects: effects,
                input: input,
                output: output,
                render: { request in
                    EffectResult(output: escaped, opposite: request.input)
                }
            )
        }

        let readOnly = try makeTexture(device: device, usage: [.shaderRead])
        requireChainError(.missingUsage(
            name: "output",
            actual: readOnly.usage.rawValue,
            required: MTLTextureUsage([.shaderRead, .renderTarget]).rawValue
        )) {
            try validatePair(input: input, output: readOnly)
        }

        print("effect-chain ping-pong invariant OK")
    }
}
