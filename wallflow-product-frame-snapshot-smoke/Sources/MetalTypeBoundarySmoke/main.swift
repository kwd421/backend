import CoreGraphics
import Foundation
import Metal

enum MetalBoundaryError: Error, Equatable {
    case invalidBounds(width: Double, height: Double)
    case status(MTLCommandBufferStatus)
}

@main
struct MetalTypeBoundarySmoke {
    static func main() {
        let width: CGFloat = 1920
        let height: CGFloat = 1080
        let boundsError: MetalBoundaryError = .invalidBounds(
            width: width,
            height: height
        )
        guard boundsError == .invalidBounds(width: 1920, height: 1080) else {
            fatalError("CGFloat-to-Double product-boundary conversion changed")
        }
        guard MetalBoundaryError.status(.notEnqueued)
            == MetalBoundaryError.status(.notEnqueued) else {
            fatalError("MTLCommandBufferStatus is not stable in an Equatable error payload")
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            print("SKIP: no Metal command buffer")
            return
        }
        guard commandBuffer.status == .notEnqueued else {
            fatalError("fresh command buffer is not in the expected not-enqueued state")
        }
        print("PASS: Metal/CoreGraphics type boundaries")
    }
}
