import Darwin
import Foundation
import Metal

private final class CompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var statusRawValue: UInt?
    private var errorDescription: String?

    func record(_ commandBuffer: MTLCommandBuffer) {
        lock.lock()
        statusRawValue = commandBuffer.status.rawValue
        errorDescription = commandBuffer.error?.localizedDescription
        lock.unlock()
    }

    func snapshot() -> (UInt?, String?) {
        lock.lock()
        defer { lock.unlock() }
        return (statusRawValue, errorDescription)
    }
}

guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue(),
      let commandBuffer = queue.makeCommandBuffer() else {
    fputs("METAL_SENDABLE_COMPLETION_FAILED: Metal is unavailable\n", stderr)
    exit(EXIT_FAILURE)
}

let box = CompletionBox()
let semaphore = DispatchSemaphore(value: 0)
commandBuffer.addCompletedHandler { @Sendable completedBuffer in
    box.record(completedBuffer)
    semaphore.signal()
}
commandBuffer.commit()
commandBuffer.waitUntilCompleted()

let callback = box.snapshot()
guard commandBuffer.status == .completed,
      semaphore.wait(timeout: .now() + 5) == .success,
      callback.0 == MTLCommandBufferStatus.completed.rawValue else {
    fputs(
        "METAL_SENDABLE_COMPLETION_FAILED: waited=\(commandBuffer.status.rawValue) callback=\(String(describing: callback.0)) error=\(callback.1 ?? "none")\n",
        stderr
    )
    exit(EXIT_FAILURE)
}

print("METAL_SENDABLE_COMPLETION_OK device=\(device.name)")
