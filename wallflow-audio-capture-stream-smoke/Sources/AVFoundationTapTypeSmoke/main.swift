@preconcurrency import AVFoundation
import Foundation

private final class TapSink: @unchecked Sendable {
    func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return }

        let left = Array(
            UnsafeBufferPointer(start: channels[0], count: frameCount)
        )
        let right = channelCount > 1
            ? Array(UnsafeBufferPointer(start: channels[1], count: frameCount))
            : left
        precondition(left.count == right.count)
    }
}

/// This function is intentionally type-checked but not executed on a headless runner. It proves
/// the Swift 6 boundary used by the private product adapter without requiring an audio device.
@MainActor
private func compileAVAudioEngineTapBoundary() {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let sink = TapSink()
    engine.attach(player)

    guard let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    ), let sourceBuffer = AVAudioPCMBuffer(
        pcmFormat: sourceFormat,
        frameCapacity: 256
    ) else {
        return
    }
    sourceBuffer.frameLength = 256

    engine.connect(
        player,
        to: engine.mainMixerNode,
        format: sourceFormat
    )
    let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
    if tapFormat.channelCount > 0 {
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: tapFormat
        ) { [sink] buffer, _ in
            sink.consume(buffer)
        }
        engine.mainMixerNode.removeTap(onBus: 0)
    }

    player.scheduleBuffer(sourceBuffer, at: nil, options: [.loops])
    player.volume = 0.5
    player.pause()
    player.stop()
    engine.stop()
}

print("PASS: AVAudioEngine tap producer boundary type-checked")
