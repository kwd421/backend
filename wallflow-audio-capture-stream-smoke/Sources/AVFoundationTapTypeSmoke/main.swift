@preconcurrency import AVFoundation
import Foundation

private enum TapFailure: Error, Equatable, Sendable {
    case configurationChanged
    case invalidFormat
    case missingChannels
    case nonFinitePCM
}

private final class TapFailureState: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: TapFailure?

    func record(_ failure: TapFailure) {
        lock.lock()
        if self.failure == nil {
            self.failure = failure
        }
        lock.unlock()
    }
}

private final class TapSink: @unchecked Sendable {
    private let expectedSampleRate: Double
    private let failureState: TapFailureState

    init(expectedSampleRate: Double, failureState: TapFailureState) {
        self.expectedSampleRate = expectedSampleRate
        self.failureState = failureState
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        let format = buffer.format
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              format.channelCount == 2,
              format.sampleRate == expectedSampleRate else {
            failureState.record(.invalidFormat)
            return
        }
        guard let channels = buffer.floatChannelData else {
            failureState.record(.missingChannels)
            return
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let left = Array(
            UnsafeBufferPointer(start: channels[0], count: frameCount)
        )
        let right = Array(
            UnsafeBufferPointer(start: channels[1], count: frameCount)
        )
        guard left.allSatisfy(\.isFinite), right.allSatisfy(\.isFinite) else {
            failureState.record(.nonFinitePCM)
            return
        }
        precondition(left.count == right.count)
    }
}

/// This function is intentionally type-checked but not executed on a headless runner. It proves
/// the complete AVAudioEngine/tap/configuration boundary used by the private product adapter.
@MainActor
private func compileAVAudioEngineTapBoundary() throws {
    let frameCount = 256
    precondition(frameCount <= Int(AVAudioFrameCount.max))
    guard let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    ), let sourceBuffer = AVAudioPCMBuffer(
        pcmFormat: sourceFormat,
        frameCapacity: AVAudioFrameCount(frameCount)
    ), let sourceChannels = sourceBuffer.floatChannelData else {
        return
    }
    sourceBuffer.frameLength = AVAudioFrameCount(frameCount)
    let left = [Float](repeating: 0, count: frameCount)
    let right = [Float](repeating: 0, count: frameCount)
    left.withUnsafeBufferPointer { samples in
        sourceChannels[0].update(from: samples.baseAddress!, count: frameCount)
    }
    right.withUnsafeBufferPointer { samples in
        sourceChannels[1].update(from: samples.baseAddress!, count: frameCount)
    }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let failureState = TapFailureState()
    let sink = TapSink(
        expectedSampleRate: sourceFormat.sampleRate,
        failureState: failureState
    )
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: sourceFormat)
    engine.mainMixerNode.installTap(
        onBus: 0,
        bufferSize: 1_024,
        format: sourceFormat
    ) { [sink] buffer, _ in
        sink.consume(buffer)
    }
    player.scheduleBuffer(sourceBuffer, at: nil, options: [.loops])
    player.volume = 0.5

    let observer = NotificationCenter.default.addObserver(
        forName: .AVAudioEngineConfigurationChange,
        object: engine,
        queue: nil
    ) { [failureState] _ in
        failureState.record(.configurationChanged)
    }

    engine.prepare()
    try engine.start()
    player.play()
    player.pause()
    engine.pause()
    player.stop()
    engine.mainMixerNode.removeTap(onBus: 0)
    engine.stop()
    NotificationCenter.default.removeObserver(observer)
}

print("PASS: complete AVAudioEngine publication producer boundary type-checked")
