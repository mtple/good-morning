import AppKit
import AVFoundation

/// An optional typewriter sound as you type: a clack for each key, a heavier one for the space bar, a lighter one
/// for Delete, and a ratchet and thump for Return. Off unless turned on in Settings or the command palette.
///
/// The sounds are made up in code when first needed, so there's no recording to ship, and each kind has a few
/// variations picked at random so a run of letters doesn't sound like a machine gun. Several players take turns,
/// so fast typing overlaps instead of queueing up behind itself.
///
/// The audio engine stops after a few quiet seconds. A running engine keeps the Mac's audio hardware awake,
/// and that would hold off sleep.
@MainActor
final class Typewriter {
    static let shared = Typewriter()

    enum Stroke: CaseIterable {
        case key, space, delete, carriageReturn
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var sounds: [Stroke: [AVAudioPCMBuffer]] = [:]
    private var idleStop: Task<Void, Never>?

    private init() {}

    /// The sound a key press makes, or nil for keys that don't type (arrows, function keys, shortcuts) and for
    /// a key held down, which would rattle.
    static func stroke(for event: NSEvent) -> Stroke? {
        guard !event.isARepeat, event.modifierFlags.intersection([.command, .control]).isEmpty else { return nil }
        switch event.keyCode {
        case 36, 76: return .carriageReturn  // Return, and Enter on the keypad
        case 49: return .space
        case 51, 117: return .delete  // Delete, and Forward Delete
        default:
            // AppKit puts arrows, function keys and the like in the private-use range.
            guard let character = event.characters?.unicodeScalars.first,
                  !(0xF700...0xF8FF).contains(character.value), character.value != 0x1B else { return nil }
            return .key
        }
    }

    /// Does nothing while the sound is off.
    func play(_ stroke: Stroke) {
        guard Prefs.typingSound else {
            stop()
            return
        }
        guard start(), let buffer = sounds[stroke]?.randomElement() else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = Float.random(in: 0.75...1)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()  // no-op if it's already playing
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            guard (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            self?.stop()
        }
    }

    /// True once the engine is running.
    private func start() -> Bool {
        guard let format else { return false }
        if players.isEmpty {
            for _ in 0..<6 {
                let player = AVAudioPlayerNode()
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                players.append(player)
            }
            engine.mainMixerNode.outputVolume = 0.5
            sounds = Self.makeSounds(format: format)
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                return false  // no output device, say. Typing carries on in silence.
            }
        }
        return true
    }

    private func stop() {
        idleStop?.cancel()
        idleStop = nil
        guard engine.isRunning else { return }
        players.forEach { $0.stop() }
        engine.stop()
    }

    // MARK: Sounds

    private static func makeSounds(format: AVAudioFormat) -> [Stroke: [AVAudioPCMBuffer]] {
        let rate = format.sampleRate
        func sound(seconds: Double, _ draw: (inout [Float]) -> Void) -> AVAudioPCMBuffer? {
            let frames = AVAudioFrameCount(seconds * rate)
            var samples = [Float](repeating: 0, count: Int(frames))
            draw(&samples)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = frames
            for (index, sample) in samples.enumerated() { channel[index] = max(-1, min(1, sample)) }
            return buffer
        }
        func variations(_ count: Int, seconds: Double, _ draw: @escaping (inout [Float]) -> Void) -> [AVAudioPCMBuffer] {
            (0..<count).compactMap { _ in sound(seconds: seconds, draw) }
        }
        return [
            .key: variations(4, seconds: 0.1) {
                strike(&$0, rate: rate, click: 0.5, thunk: 0.25, pitch: .random(in: 170...230))
            },
            .space: variations(3, seconds: 0.12) {
                strike(&$0, rate: rate, click: 0.25, thunk: 0.4, pitch: .random(in: 105...130))
            },
            .delete: variations(3, seconds: 0.08) {
                strike(&$0, rate: rate, click: 0.35, thunk: 0.12, pitch: .random(in: 260...300))
            },
            .carriageReturn: variations(2, seconds: 0.3) { samples in
                // The carriage ratcheting back, then landing.
                for notch in 0..<8 {
                    strike(&samples, rate: rate, at: 0.015 * Double(notch), click: 0.12, thunk: 0, pitch: 0)
                }
                strike(&samples, rate: rate, at: 0.16, click: 0.6, thunk: 0.5, pitch: .random(in: 130...150))
            },
        ]
    }

    /// One type bar hitting the platen, added into `samples` at `offset` seconds: a bright tick of noise that dies
    /// away almost at once, over a low knock that lasts a little longer.
    private static func strike(_ samples: inout [Float], rate: Double, at offset: Double = 0,
                               click: Float, thunk: Float, pitch: Double) {
        let start = Int(offset * rate)
        let length = Int(0.09 * rate)
        var last: Float = 0
        for index in 0..<length where start + index < samples.count {
            let time = Double(index) / rate
            let noise = Float.random(in: -1...1)
            let tick = (noise - last) * click * Float(exp(-time * 300))  // the difference keeps only the bright part
            last = noise
            let knock = Float(sin(2 * .pi * pitch * time) * exp(-time * 60)) * thunk
            samples[start + index] += tick + knock
        }
    }
}
