import Foundation
import Metal

enum TargetStoreError: Error, Equatable {
    case noDevice
    case invalidAuthoredObjectIndex(Int)
    case invalidDimensions(width: Int, height: Int)
    case textureAllocationFailed(role: String)
    case aliasedTexturePair
}

@MainActor
final class ImageLayerRenderTargetStore {
    struct Identity: Hashable {
        let packageSHA256: String
        let authoredObjectIndex: Int
    }

    struct Specification: Equatable {
        let width: Int
        let height: Int
        let pixelFormat: MTLPixelFormat
    }

    struct Pair {
        let identity: Identity
        let specification: Specification
        let input: MTLTexture
        let output: MTLTexture
    }

    private struct StoredPair {
        let specification: Specification
        let input: MTLTexture
        let output: MTLTexture
    }

    private let device: MTLDevice
    private var pairs: [Identity: StoredPair] = [:]

    init(device: MTLDevice) {
        self.device = device
    }

    func pair(
        identity: Identity,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat
    ) throws -> Pair {
        guard identity.authoredObjectIndex >= 0 else {
            throw TargetStoreError.invalidAuthoredObjectIndex(
                identity.authoredObjectIndex
            )
        }
        guard width > 0, height > 0 else {
            throw TargetStoreError.invalidDimensions(
                width: width,
                height: height
            )
        }
        let specification = Specification(
            width: width,
            height: height,
            pixelFormat: pixelFormat
        )
        if let stored = pairs[identity], stored.specification == specification {
            return Pair(
                identity: identity,
                specification: specification,
                input: stored.input,
                output: stored.output
            )
        }

        let input = try makeTexture(specification: specification, role: "input")
        let output = try makeTexture(specification: specification, role: "output")
        guard input !== output else {
            throw TargetStoreError.aliasedTexturePair
        }
        input.label = label(identity: identity, role: "input")
        output.label = label(identity: identity, role: "output")
        pairs[identity] = StoredPair(
            specification: specification,
            input: input,
            output: output
        )
        return Pair(
            identity: identity,
            specification: specification,
            input: input,
            output: output
        )
    }

    func removeAll() {
        pairs.removeAll()
    }

    private func makeTexture(
        specification: Specification,
        role: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: specification.pixelFormat,
            width: specification.width,
            height: specification.height,
            mipmapped: false
        )
        descriptor.textureType = .type2D
        descriptor.arrayLength = 1
        descriptor.sampleCount = 1
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw TargetStoreError.textureAllocationFailed(role: role)
        }
        return texture
    }

    private func label(identity: Identity, role: String) -> String {
        "WPE \(identity.packageSHA256.prefix(12)) object \(identity.authoredObjectIndex) \(role)"
    }
}

func requireTargetStoreError(
    _ expected: TargetStoreError,
    operation: () throws -> Void
) {
    do {
        try operation()
        preconditionFailure("Expected \(expected)")
    } catch let actual as TargetStoreError {
        precondition(actual == expected, "Expected \(expected), got \(actual)")
    } catch {
        preconditionFailure("Unexpected error \(error)")
    }
}

@main
struct Main {
    @MainActor
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw TargetStoreError.noDevice
        }
        let store = ImageLayerRenderTargetStore(device: device)
        let firstIdentity = ImageLayerRenderTargetStore.Identity(
            packageSHA256: String(repeating: "a", count: 64),
            authoredObjectIndex: 3
        )
        let secondIdentity = ImageLayerRenderTargetStore.Identity(
            packageSHA256: String(repeating: "a", count: 64),
            authoredObjectIndex: 4
        )

        let first = try store.pair(
            identity: firstIdentity,
            width: 320,
            height: 180,
            pixelFormat: .bgra8Unorm
        )
        let repeated = try store.pair(
            identity: firstIdentity,
            width: 320,
            height: 180,
            pixelFormat: .bgra8Unorm
        )
        let second = try store.pair(
            identity: secondIdentity,
            width: 320,
            height: 180,
            pixelFormat: .bgra8Unorm
        )
        precondition(first.input === repeated.input)
        precondition(first.output === repeated.output)
        precondition(first.input !== first.output)
        precondition(first.input !== second.input)
        precondition(first.output !== second.output)
        precondition(first.input.usage.contains(.shaderRead))
        precondition(first.input.usage.contains(.renderTarget))
        precondition(first.output.usage.contains(.shaderRead))
        precondition(first.output.usage.contains(.renderTarget))
        precondition(first.input.storageMode == .private)
        precondition(first.output.storageMode == .private)
        precondition(first.input.label == "WPE aaaaaaaaaaaa object 3 input")
        precondition(first.output.label == "WPE aaaaaaaaaaaa object 3 output")

        let resized = try store.pair(
            identity: firstIdentity,
            width: 640,
            height: 360,
            pixelFormat: .bgra8Unorm
        )
        precondition(resized.input !== first.input)
        precondition(resized.output !== first.output)

        let hdr = try store.pair(
            identity: firstIdentity,
            width: 640,
            height: 360,
            pixelFormat: .rgba16Float
        )
        let repeatedHDR = try store.pair(
            identity: firstIdentity,
            width: 640,
            height: 360,
            pixelFormat: .rgba16Float
        )
        precondition(hdr.input !== resized.input)
        precondition(hdr.output !== resized.output)
        precondition(hdr.input === repeatedHDR.input)
        precondition(hdr.output === repeatedHDR.output)
        precondition(hdr.input.pixelFormat == .rgba16Float)
        precondition(hdr.output.pixelFormat == .rgba16Float)

        store.removeAll()
        let afterRemoval = try store.pair(
            identity: firstIdentity,
            width: 640,
            height: 360,
            pixelFormat: .rgba16Float
        )
        precondition(afterRemoval.input !== hdr.input)
        precondition(afterRemoval.output !== hdr.output)

        requireTargetStoreError(.invalidAuthoredObjectIndex(-1)) {
            _ = try store.pair(
                identity: .init(packageSHA256: "package", authoredObjectIndex: -1),
                width: 1,
                height: 1,
                pixelFormat: .bgra8Unorm
            )
        }
        requireTargetStoreError(.invalidDimensions(width: 0, height: 1)) {
            _ = try store.pair(
                identity: .init(packageSHA256: "package", authoredObjectIndex: 0),
                width: 0,
                height: 1,
                pixelFormat: .bgra8Unorm
            )
        }

        print("ImageLayer render-target store invariant OK")
    }
}
