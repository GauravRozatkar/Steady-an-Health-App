import Foundation
import CoreHaptics
import AVFoundation
import UIKit

// MARK: - Vocabulary
// The rest of the app speaks in these small enums and never touches
// CoreHaptics or AVAudioEngine directly. That keeps every failure path
// (no haptic hardware, audio route changes, interruptions) in one file.

enum BreathKind {
    case inhale, hold, exhale, rest
}

enum HapticCue {
    case tap, soft, selection, success
    /// The satisfying "frost clears" pattern used by the grounding cards.
    case clear(step: Int)
}

enum Chime {
    case inhale, hold, exhale, complete
    /// A single pentatonic note. Any index works, so a journey can climb.
    case step(Int)
}

enum NoiseKind: String, CaseIterable, Identifiable {
    case brown, pink

    var id: String { rawValue }
    var title: String {
        switch self {
        case .brown: "Brown noise"
        case .pink: "Pink noise"
        }
    }
}

// MARK: - Noise generator
// Runs on the real-time audio thread, so it is a plain final class with
// simple value state and no locks, allocations or actor hops. The two
// public fields are written from the main thread and read by the audio
// thread; a stale read for one buffer is harmless for a gain or a mode.

final class NoiseGenerator: @unchecked Sendable {
    var kind: NoiseKind = .brown
    var targetGain: Float = 0

    private var gain: Float = 0
    private var brownLast: Float = 0
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0
    private var b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0

    func render(frames: Int, into buffer: UnsafeMutablePointer<Float>) {
        for n in 0..<frames {
            // Slow one-pole smoothing: volume changes and stop/start fade in
            // and out over a few hundred milliseconds, never click.
            gain += (targetGain - gain) * 0.00008
            let white = Float.random(in: -1...1)
            let sample: Float
            switch kind {
            case .brown:
                // Leaky integration of white noise gives a deep, rumbling spectrum.
                brownLast = (brownLast + 0.02 * white) / 1.02
                sample = brownLast * 3.2
            case .pink:
                // Paul Kellet's economical pink filter.
                b0 = 0.99886 * b0 + white * 0.0555179
                b1 = 0.99332 * b1 + white * 0.0750759
                b2 = 0.96900 * b2 + white * 0.1538520
                b3 = 0.86650 * b3 + white * 0.3104856
                b4 = 0.55000 * b4 + white * 0.5329522
                b5 = -0.7616 * b5 - white * 0.0168980
                sample = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.11
                b6 = white * 0.115926
            }
            buffer[n] = max(-1, min(1, sample)) * gain
        }
    }
}

// Built outside the main-actor engine so the render closure is not
// main-actor isolated: it is called from the audio thread.
enum NoiseNodeFactory {
    static func make(generator: NoiseGenerator, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let raw = buffer.mData else { continue }
                let pointer = raw.assumingMemoryBound(to: Float.self)
                generator.render(frames: Int(frameCount), into: pointer)
            }
            return noErr
        }
    }
}

// MARK: - Engine

@MainActor
final class HapticAudioEngine {
    static let shared = HapticAudioEngine()
    private init() {}

    /// Mirrored from the settings sheet.
    var hapticsEnabled = true
    var soundEnabled = true

    /// False on most iPads without a Taptic Engine, Mac, and the Simulator.
    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    // Haptics
    private var hapticEngine: CHHapticEngine?
    private var activePlayers: [CHHapticPatternPlayer] = []
    private var fallbackTask: Task<Void, Never>?

    // Audio
    private let audioEngine = AVAudioEngine()
    private let chimePlayer = AVAudioPlayerNode()
    private let sampleRate = 44_100.0
    private lazy var monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    private var chimeCache: [String: AVAudioPCMBuffer] = [:]
    private let noise = NoiseGenerator()
    private var noiseNode: AVAudioSourceNode?
    private var audioConfigured = false

    // MARK: Setup

    /// Safe to call repeatedly. Nothing here can throw to the caller.
    func prepare() {
        prepareHaptics()
        prepareAudio()
    }

    private func prepareHaptics() {
        guard supportsHaptics, hapticEngine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            // The engine sleeps when idle to save power. readyEngine() restarts it.
            engine.isAutoShutdownEnabled = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in self?.restartHaptics() }
            }
            try engine.start()
            hapticEngine = engine
        } catch {
            hapticEngine = nil // fall back to UIKit generators
        }
    }

    private func restartHaptics() {
        do { try hapticEngine?.start() } catch { hapticEngine = nil }
    }

    private func prepareAudio() {
        guard !audioConfigured else { return }
        audioConfigured = true
        do {
            let session = AVAudioSession.sharedInstance()
            // .playback keeps chimes and noise audible with the silent switch on,
            // which matters when someone is calming down. mixWithOthers lets
            // them keep their own music or white-noise app running.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio is a bonus. The app stays fully usable without it.
        }
        audioEngine.attach(chimePlayer)
        audioEngine.connect(chimePlayer, to: audioEngine.mainMixerNode, format: monoFormat)
        chimePlayer.volume = 0.7
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in _ = self?.ensureAudioRunning() }
        }
        audioEngine.prepare()
    }

    @discardableResult
    private func ensureAudioRunning() -> Bool {
        prepareAudio()
        if !audioEngine.isRunning {
            do { try audioEngine.start() } catch { return false }
        }
        if !chimePlayer.isPlaying { chimePlayer.play() }
        return true
    }

    /// Call when leaving a screen that used sound. Fades noise, then idles the engine.
    func suspendAudio() {
        noise.targetGain = 0
        Task { @MainActor [self] in
            try? await Task.sleep(for: .milliseconds(700))
            if noise.targetGain == 0 { audioEngine.pause() }
        }
    }

    // MARK: Haptic cues

    func cue(_ cue: HapticCue) {
        guard hapticsEnabled else { return }
        if let engine = readyEngine() {
            do {
                try play(events: events(for: cue), on: engine)
                return
            } catch {
                // fall through to the UIKit fallback
            }
        }
        fallback(cue)
    }

    /// One breathing phase as a haptic shape: a swell for inhale, a fade for
    /// exhale, soft ticks for hold. With `heartbeat` the phase becomes a
    /// lub-dub rhythm whose pace rises on inhale and settles on exhale.
    func breath(_ kind: BreathKind, duration: TimeInterval, heartbeat: Bool = false) {
        guard hapticsEnabled else { return }
        stopHaptics()
        guard kind != .rest else { return }
        if let engine = readyEngine() {
            do {
                let pattern = breathPattern(kind, duration: duration, heartbeat: heartbeat)
                try play(events: pattern.events, curves: pattern.curves, on: engine)
                return
            } catch {
                // fall through
            }
        }
        fallbackBreath(duration: duration)
    }

    func stopHaptics() {
        fallbackTask?.cancel()
        fallbackTask = nil
        for player in activePlayers {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        activePlayers.removeAll()
    }

    // MARK: Chimes and noise

    func chime(_ chime: Chime) {
        guard soundEnabled, ensureAudioRunning() else { return }
        let recipe = recipe(for: chime)
        let buffer: AVAudioPCMBuffer
        if let cached = chimeCache[recipe.key] {
            buffer = cached
        } else {
            buffer = makeBuffer(recipe)
            chimeCache[recipe.key] = buffer
        }
        chimePlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    func startNoise(_ kind: NoiseKind, volume: Float) {
        guard soundEnabled, ensureAudioRunning() else { return }
        noise.kind = kind
        if noiseNode == nil {
            let node = NoiseNodeFactory.make(generator: noise, format: monoFormat)
            audioEngine.attach(node)
            audioEngine.connect(node, to: audioEngine.mainMixerNode, format: monoFormat)
            noiseNode = node
        }
        noise.targetGain = volume
    }

    func setNoiseVolume(_ volume: Float) {
        noise.targetGain = soundEnabled ? volume : 0
    }

    func stopNoise() {
        noise.targetGain = 0
    }

    // MARK: Haptic internals

    private func readyEngine() -> CHHapticEngine? {
        guard supportsHaptics else { return nil }
        if hapticEngine == nil { prepareHaptics() }
        guard let engine = hapticEngine else { return nil }
        do {
            try engine.start()
            return engine
        } catch {
            return nil
        }
    }

    private func play(
        events: [CHHapticEvent],
        curves: [CHHapticParameterCurve] = [],
        on engine: CHHapticEngine
    ) throws {
        let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: CHHapticTimeImmediate)
        activePlayers.append(player)
        if activePlayers.count > 12 { activePlayers.removeFirst() }
    }

    private func transient(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
    }

    private func continuous(_ time: TimeInterval, _ duration: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time,
            duration: duration
        )
    }

    private func events(for cue: HapticCue) -> [CHHapticEvent] {
        switch cue {
        case .tap:
            return [transient(0, 0.6, 0.5)]
        case .soft:
            return [transient(0, 0.35, 0.2)]
        case .selection:
            return [transient(0, 0.45, 0.8)]
        case .success:
            return [transient(0, 0.5, 0.4), transient(0.12, 0.9, 0.6)]
        case .clear(let step):
            // A quick rising swish, then a soft pop. Later steps are slightly
            // crisper so the journey feels like it is lifting.
            let sharp = Float(min(0.9, 0.3 + 0.1 * Double(step)))
            return [continuous(0, 0.22, 0.5, 0.15), transient(0.22, 0.85, sharp)]
        }
    }

    private func breathPattern(
        _ kind: BreathKind,
        duration: TimeInterval,
        heartbeat: Bool
    ) -> (events: [CHHapticEvent], curves: [CHHapticParameterCurve]) {
        // A single continuous event is limited to 30 seconds.
        let length = min(duration, 29)

        if heartbeat {
            var events: [CHHapticEvent] = []
            let startGap: Double
            let endGap: Double
            switch kind {
            case .inhale: startGap = 0.95; endGap = 0.75
            case .exhale: startGap = 0.75; endGap = 1.15
            default: startGap = 0.9; endGap = 0.9
            }
            var time = 0.0
            while time < length - 0.3 {
                let progress = time / length
                let strength = kind == .exhale ? 0.85 - 0.45 * progress : 0.45 + 0.4 * progress
                events.append(transient(time, Float(strength), 0.35))
                events.append(transient(time + 0.17, Float(strength * 0.7), 0.25))
                time += startGap + (endGap - startGap) * progress
            }
            return (events, [])
        }

        switch kind {
        case .inhale:
            return ([continuous(0, length, 1.0, 0.25)], [intensityCurve(length, [0.08, 0.45, 0.85])])
        case .exhale:
            return ([continuous(0, length, 1.0, 0.2)], [intensityCurve(length, [0.8, 0.35, 0.04])])
        case .hold:
            var ticks: [CHHapticEvent] = []
            var time = 0.0
            while time < length {
                ticks.append(transient(time, 0.22, 0.2))
                time += 1.0
            }
            return (ticks, [])
        case .rest:
            return ([], [])
        }
    }

    /// Evenly spaced control points that scale the event's intensity over time.
    private func intensityCurve(_ length: TimeInterval, _ values: [Float]) -> CHHapticParameterCurve {
        let points = values.enumerated().map { index, value in
            CHHapticParameterCurve.ControlPoint(
                relativeTime: length * Double(index) / Double(max(1, values.count - 1)),
                value: value
            )
        }
        return CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: points, relativeTime: 0)
    }

    // MARK: Fallbacks (no CHHapticEngine)
    // UIKit feedback generators work on every iPhone and quietly do nothing on
    // hardware without a Taptic Engine, so these can never crash.

    private func fallback(_ cue: HapticCue) {
        switch cue {
        case .tap:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .soft, .clear:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func fallbackBreath(duration: TimeInterval) {
        fallbackTask?.cancel()
        fallbackTask = Task { @MainActor in
            let generator = UIImpactFeedbackGenerator(style: .soft)
            var elapsed = 0.0
            while elapsed < duration && !Task.isCancelled {
                generator.impactOccurred(intensity: 0.5)
                try? await Task.sleep(for: .seconds(1))
                elapsed += 1
            }
        }
    }

    // MARK: Chime synthesis
    // Bell-like tones from a few decaying sine partials, rendered once into a
    // PCM buffer and cached. No audio files are bundled.

    private struct ChimeNote {
        let midi: Int
        let start: Double
    }

    private struct ChimeRecipe {
        let key: String
        let notes: [ChimeNote]
        let length: Double
    }

    private func recipe(for chime: Chime) -> ChimeRecipe {
        switch chime {
        case .inhale:
            return ChimeRecipe(key: "inhale", notes: [ChimeNote(midi: 72, start: 0), ChimeNote(midi: 79, start: 0.22)], length: 2.6)
        case .hold:
            return ChimeRecipe(key: "hold", notes: [ChimeNote(midi: 76, start: 0)], length: 2.4)
        case .exhale:
            return ChimeRecipe(key: "exhale", notes: [ChimeNote(midi: 79, start: 0), ChimeNote(midi: 72, start: 0.22)], length: 2.8)
        case .complete:
            let notes = [72, 76, 79, 84].enumerated().map { ChimeNote(midi: $0.element, start: Double($0.offset) * 0.25) }
            return ChimeRecipe(key: "complete", notes: notes, length: 3.6)
        case .step(let index):
            // C major pentatonic over two octaves: any sequence sounds pleasant.
            let scale = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81]
            let note = scale[abs(index) % scale.count] + 12
            return ChimeRecipe(key: "step-\(note)", notes: [ChimeNote(midi: note, start: 0)], length: 2.0)
        }
    }

    private func makeBuffer(_ recipe: ChimeRecipe) -> AVAudioPCMBuffer {
        let totalFrames = Int(recipe.length * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)
        let data = buffer.floatChannelData![0]
        for index in 0..<totalFrames { data[index] = 0 }

        // ratio, gain, decay rate. The slightly inharmonic top partial gives the bell color.
        let partials: [(ratio: Double, gain: Double, decay: Double)] = [
            (1.0, 1.0, 2.2), (2.0, 0.35, 3.0), (3.0, 0.18, 4.0), (4.2, 0.08, 6.0)
        ]

        for note in recipe.notes {
            let frequency = 440.0 * pow(2.0, Double(note.midi - 69) / 12.0)
            let startFrame = Int(note.start * sampleRate)
            guard startFrame < totalFrames else { continue }
            for frame in startFrame..<totalFrames {
                let t = Double(frame - startFrame) / sampleRate
                let attack = min(1.0, t / 0.012)
                var sum = 0.0
                for partial in partials {
                    let wave = sin(2.0 * Double.pi * frequency * partial.ratio * t)
                    sum += partial.gain * wave * exp(-partial.decay * t)
                }
                data[frame] += Float(0.22 * attack * sum)
            }
        }
        return buffer
    }
}
