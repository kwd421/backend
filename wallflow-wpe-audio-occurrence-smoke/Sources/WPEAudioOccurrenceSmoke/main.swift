@preconcurrency import AVFoundation
import Foundation

struct ExactAsset: Equatable, Sendable {
    let packageSHA256: String
    let authoredPath: String
    let rawPath: String
    let bytes: Data
}

enum OccurrenceError: Error, Equatable {
    case invalidGain(Float)
}

struct PlaybackOccurrence: Equatable, Sendable {
    let asset: ExactAsset
    let gain: Float

    init(asset: ExactAsset, gain: Float) throws {
        guard gain.isFinite, (0...1).contains(gain) else {
            throw OccurrenceError.invalidGain(gain)
        }
        self.asset = asset
        self.gain = gain
    }
}

enum TransportState: Equatable, Sendable {
    case stoppedAtBeginning
    case playing
    case pausedAtCurrentTime
}

enum TransportAction: Equatable, Sendable {
    case none
    case startFromBeginning
    case resumeFromCurrentTime
    case pauseAtCurrentTime
    case stopAndResetToBeginning
}

struct Transport: Equatable, Sendable {
    private(set) var state: TransportState = .stoppedAtBeginning

    var isPlaying: Bool { state == .playing }

    mutating func play() -> TransportAction {
        switch state {
        case .playing:
            return .none
        case .pausedAtCurrentTime:
            state = .playing
            return .resumeFromCurrentTime
        case .stoppedAtBeginning:
            state = .playing
            return .startFromBeginning
        }
    }

    mutating func pause() -> TransportAction {
        guard state == .playing else { return .none }
        state = .pausedAtCurrentTime
        return .pauseAtCurrentTime
    }

    mutating func stop() -> TransportAction {
        guard state != .stoppedAtBeginning else { return .none }
        state = .stoppedAtBeginning
        return .stopAndResetToBeginning
    }
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct WPEAudioOccurrenceSmoke {
    @MainActor
    static func main() throws {
        let asset = ExactAsset(
            packageSHA256: "package",
            authoredPath: "sounds/Tone.wav",
            rawPath: "sounds/tone.WAV",
            bytes: Data([1, 2, 3, 4])
        )
        let silentOccurrence = try PlaybackOccurrence(asset: asset, gain: 0)
        require(silentOccurrence.asset == asset, "exact asset identity changed")
        require(silentOccurrence.gain == 0, "zero gain was not retained")

        do {
            _ = try PlaybackOccurrence(asset: asset, gain: -0.01)
            require(false, "negative gain was accepted")
        } catch OccurrenceError.invalidGain(let gain) {
            require(gain == -0.01, "negative gain diagnostic changed")
        }
        do {
            _ = try PlaybackOccurrence(asset: asset, gain: 1.01)
            require(false, "gain above one was accepted")
        } catch OccurrenceError.invalidGain(let gain) {
            require(gain == 1.01, "high gain diagnostic changed")
        }

        var transport = Transport()
        require(transport.play() == .startFromBeginning, "first play did not start at beginning")
        require(transport.play() == .none, "play restarted an already-running sound")
        require(transport.isPlaying, "playing state was lost")
        require(transport.pause() == .pauseAtCurrentTime, "pause did not retain current time")
        require(!transport.isPlaying, "paused sound still reports playing")
        require(transport.play() == .resumeFromCurrentTime, "play did not resume paused time")
        require(transport.stop() == .stopAndResetToBeginning, "stop did not reset timer")
        require(transport.play() == .startFromBeginning, "play after stop did not restart at beginning")

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 4
        ), let channels = buffer.floatChannelData else {
            fputs("FAIL: could not allocate stereo Float32 buffer\n", stderr)
            exit(1)
        }
        buffer.frameLength = 4
        for channel in 0..<2 {
            for frame in 0..<4 {
                channels[channel][frame] = 0
            }
        }

        let options: AVAudioPlayerNodeBufferOptions = []
        require(options.rawValue == 0, "one-shot scheduling options are not empty")
        require(!options.contains(.loops), "one-shot scheduling accidentally contains loops")

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.scheduleBuffer(buffer, at: nil, options: options)
        player.volume = silentOccurrence.gain
        player.stop()
        engine.stop()

        print("PASS: exact WPE audio occurrence and documented transport remain isolated")
    }
}
