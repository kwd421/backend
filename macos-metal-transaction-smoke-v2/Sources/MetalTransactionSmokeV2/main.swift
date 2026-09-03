import Darwin
import Foundation
import Metal

private enum SmokeError: LocalizedError {
    case noDevice
    case noCommandQueue
    case noTexture
    case noCommandBuffer
    case noRenderEncoder
    case completionTimedOut
    case commandBufferFailed(statusRawValue: UInt, message: String?)
    case completionDisagreed(statusRawValue: UInt, message: String?)

    var errorDescription: String? {
        switch self {
        case .noDevice:
            "No Metal device is available on this runner."
        case .noCommandQueue:
            "Could not create a Metal command queue."
        case .noTexture:
            "Could not allocate the smoke-test render target."
        case .noCommandBuffer:
            "Could not create a Metal command buffer."
        case .noRenderEncoder:
            "Could not create a Metal render command encoder."
        case .completionTimedOut:
            "The Metal completion handler did not run within five seconds."
        case .commandBufferFailed(let statusRawValue, let message):
            "The waited command buffer finished as status \(statusRawValue): \(message ?? "no Metal error")"
        case .completionDisagreed(let statusRawValue, let message):
            "The completion callback observed status \(statusRawValue): \(message ?? "no Metal error")"
        }
    }
}

/// Metal invokes command-buffer completion handlers on a driver-owned queue. The callback
/// is intentionally free of MainActor state and publishes only immutable scalar diagnostics.
private final class CompletionState: @unchecked Sendable {
    struct Snapshot: Sendable {
        let statusRawValue: UInt
        let errorDescription: String?
    }

    private let lock = NSLock()
    private var snapshot: Snapshot?

    func record(commandBuffer: MTLCommandBuffer) {
        let value = Snapshot(
            statusRawValue: commandBuffer.status.rawValue,
            errorDescription: commandBuffer.error?.localizedDescription
        )
        lock.lock()
        snapshot = value
        lock.unlock()
    }

    func read() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

private func runMetalTransactionSmoke() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw SmokeError.noDevice
    }
    guard let queue = device.makeCommandQueue() else {
        throw SmokeError.noCommandQueue
    }

    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm,
        width: 4,
        height: 4,
        mipmapped: false
    )
    textureDescriptor.storageMode = .private
    textureDescriptor.usage = [.renderTarget, .shaderRead]
    guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
        throw SmokeError.noTexture
    }

    guard let commandBuffer = queue.makeCommandBuffer() else {
        throw SmokeError.noCommandBuffer
    }
    commandBuffer.label = "Public exact-WPE transaction smoke"

    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(
        red: 0.125,
        green: 0.25,
        blue: 0.5,
        alpha: 1
    )
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
        throw SmokeError.noRenderEncoder
    }
    encoder.label = "Smoke clear"
    encoder.endEncoding()

    let completionState = CompletionState()
    let completionSignal = DispatchSemaphore(value: 0)
    commandBuffer.addCompletedHandler { completedBuffer in
        completionState.record(commandBuffer: completedBuffer)
        completionSignal.signal()
    }

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    guard commandBuffer.status == .completed else {
        throw SmokeError.commandBufferFailed(
            statusRawValue: commandBuffer.status.rawValue,
            message: commandBuffer.error?.localizedDescription
        )
    }
    guard completionSignal.wait(timeout: .now() + 5) == .success,
          let callback = completionState.read() else {
        throw SmokeError.completionTimedOut
    }
    guard callback.statusRawValue == MTLCommandBufferStatus.completed.rawValue else {
        throw SmokeError.completionDisagreed(
            statusRawValue: callback.statusRawValue,
            message: callback.errorDescription
        )
    }

    print("METAL_TRANSACTION_SMOKE_OK device=\(device.name) status=\(commandBuffer.status.rawValue)")
}

do {
    try runMetalTransactionSmoke()
} catch {
    fputs("METAL_TRANSACTION_SMOKE_FAILED: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
