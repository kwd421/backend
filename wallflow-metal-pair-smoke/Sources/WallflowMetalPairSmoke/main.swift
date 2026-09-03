import Darwin
import Foundation
import Metal

private enum PairError: Error {
    case noDevice
    case noQueue
    case noTexture
    case noCommandBuffer
    case noEncoder
    case aliased
    case dimensions
    case format
    case usage
    case completion
}

private final class CompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func record(_ commandBuffer: MTLCommandBuffer) {
        lock.lock()
        completed = commandBuffer.status == .completed
        lock.unlock()
    }

    func value() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }
}

private func validate(input: MTLTexture, output: MTLTexture) throws {
    guard input !== output else { throw PairError.aliased }
    guard input.width == output.width,
          input.height == output.height,
          input.depth == output.depth,
          input.arrayLength == output.arrayLength else {
        throw PairError.dimensions
    }
    guard input.pixelFormat == output.pixelFormat,
          input.textureType == output.textureType,
          input.sampleCount == output.sampleCount else {
        throw PairError.format
    }
    let required: MTLTextureUsage = [.shaderRead, .renderTarget]
    guard input.usage.contains(required), output.usage.contains(required) else {
        throw PairError.usage
    }
}

private func encodeClear(
    texture: MTLTexture,
    color: MTLClearColor,
    commandBuffer: MTLCommandBuffer
) throws {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = color
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
        throw PairError.noEncoder
    }
    encoder.endEncoding()
}

private func run() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { throw PairError.noDevice }
    guard let queue = device.makeCommandQueue() else { throw PairError.noQueue }

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: 8,
        height: 8,
        mipmapped: false
    )
    descriptor.storageMode = .private
    descriptor.usage = [.shaderRead, .renderTarget]
    guard let input = device.makeTexture(descriptor: descriptor),
          let output = device.makeTexture(descriptor: descriptor) else {
        throw PairError.noTexture
    }
    try validate(input: input, output: output)

    do {
        try validate(input: input, output: input)
        fputs("METAL_PAIR_SMOKE_FAILED: aliased pair was accepted\n", stderr)
        exit(EXIT_FAILURE)
    } catch PairError.aliased {
        // Expected fail-closed result.
    }

    guard let commandBuffer = queue.makeCommandBuffer() else {
        throw PairError.noCommandBuffer
    }
    try encodeClear(
        texture: input,
        color: MTLClearColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1),
        commandBuffer: commandBuffer
    )
    try encodeClear(
        texture: output,
        color: MTLClearColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 1),
        commandBuffer: commandBuffer
    )

    let box = CompletionBox()
    let semaphore = DispatchSemaphore(value: 0)
    commandBuffer.addCompletedHandler { buffer in
        box.record(buffer)
        semaphore.signal()
    }
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    guard commandBuffer.status == .completed,
          semaphore.wait(timeout: .now() + 5) == .success,
          box.value() else {
        throw PairError.completion
    }
    print("WALLFLOW_METAL_PAIR_SMOKE_OK device=\(device.name)")
}

do {
    try run()
} catch {
    fputs("WALLFLOW_METAL_PAIR_SMOKE_FAILED: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
