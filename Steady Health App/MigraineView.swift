import SwiftUI
import UIKit

// Migraine and sensory overload: one tap enters a dim, warm amber-on-charcoal
// "quiet room". Inside: a slow pulsing haptic guide, procedural brown or pink
// noise, and press-and-hold temple pads. Nothing flashes, and every control is
// large because pain makes precise tapping hard.

struct MigraineView: View {
    @Environment(AppState.self) private var state
    @State private var showSanctuary = false

    private let palette = CareModule.migraine.palette
    private let engine = HapticAudioEngine.shared

    var body: some View {
        ModuleScaffold(module: .migraine) {
            CalmPanel(palette: palette, title: "When light and sound hurt", symbol: "moon.stars.fill") {
                Text("One tap turns everything down: warm amber on charcoal, low brightness, no motion that rushes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                Button {
                    engine.cue(.soft)
                    showSanctuary = true
                } label: {
                    Label("Enter the quiet room", systemImage: "moon.fill")
                }
                .buttonStyle(CalmButtonStyle(tint: palette.deep))
                .accessibilityHint("Dims the screen and opens calming tools")
            }

            CalmPanel(palette: palette, title: "Inside the quiet room", symbol: "sparkles") {
                feature("waveform", "Brown or pink noise, generated on the device")
                feature("hand.tap.fill", "Hold a temple pad for a slow, guided 30 seconds")
                feature("heart.circle.fill", "A gentle pulse to breathe with, felt in your hands")
                feature("sun.min.fill", "Screen brightness lowered, then restored when you leave")
            }

            CalmPanel(palette: palette, title: "While you rest", symbol: "cup.and.saucer.fill") {
                feature("snowflake", "A cool cloth on your forehead or neck")
                feature("drop.fill", "Small sips of water")
                feature("curtains.closed", "Close curtains and silence notifications")
                feature("hand.raised.fill", "Nothing else to do. Resting is enough.")
            }

            SafetyNote(text: "Seek urgent medical care for a sudden, severe headache, or one with weakness, confusion, trouble speaking, vision loss, fever with a stiff neck, or after a head injury.")
        }
        .fullScreenCover(isPresented: $showSanctuary) {
            SanctuaryView()
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(palette.deep)
        }
    }
}

// MARK: - Screen dimming

/// Lowers real screen brightness while the quiet room is open and always puts
/// it back. On devices where brightness cannot be set it simply does nothing.
@MainActor
final class ScreenDimmer {
    private var original: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }

    func dim(to level: CGFloat) {
        guard let screen else { return }
        if original == nil { original = screen.brightness }
        screen.brightness = level
    }

    func restore() {
        guard let screen, let original else { return }
        screen.brightness = original
        self.original = nil
    }
}

// MARK: - Sanctuary

private struct SanctuaryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var session = BreathingSession()
    @State private var noiseOn = false
    @State private var noiseKind: NoiseKind = .brown
    @State private var volume = 0.35
    @State private var dimness = 0.08
    @State private var dimmer = ScreenDimmer()

    private let engine = HapticAudioEngine.shared

    var body: some View {
        ZStack {
            Theme.charcoal.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 30) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Leave quiet room", systemImage: "xmark")
                    }
                    .buttonStyle(CalmButtonStyle(tint: Theme.ember, prominent: false))

                    pulseSection
                    templeSection
                    noiseSection
                    dimSection

                    Text("Nothing here flashes. Every color is warm and low.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ember.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding()
                .readableColumn(maxWidth: 640)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
        // Pain makes precise tapping hard, so this room always uses High-Focus sizing.
        .environment(\.highFocus, true)
        .onAppear {
            dimmer.dim(to: CGFloat(dimness))
            state.sanctuaryVisits += 1
        }
        .onDisappear {
            session.stop()
            engine.stopNoise()
            engine.suspendAudio()
            dimmer.restore()
        }
        .onChange(of: scenePhase) { _, phase in
            // Never leave the phone dim after the app is backgrounded.
            if phase == .active {
                dimmer.dim(to: CGFloat(dimness))
            } else {
                dimmer.restore()
            }
        }
    }

    // MARK: Pulse

    private var pulseSection: some View {
        VStack(spacing: 14) {
            TimelineView(.animation(paused: reduceMotion && session.state != .running)) { context in
                let snap = session.snapshot(at: context.date, idleLevel: 0.35)
                VStack(spacing: 10) {
                    OrbCanvas(level: snap.level)
                        .aspectRatio(1.4, contentMode: .fit)
                        .accessibilityHidden(true)
                    Text(session.state == .running ? (snap.phase?.title ?? "") : "Slow pulse")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.ember)
                }
            }
            Button {
                if session.state == .running {
                    session.stop()
                } else {
                    // Quiet by design: haptics only, no chimes, no announcements.
                    session.start(BreathPlan.slowPulse(), announce: false)
                }
            } label: {
                Label(session.state == .running ? "Stop pulse" : "Start gentle pulse",
                      systemImage: session.state == .running ? "stop.fill" : "heart.fill")
            }
            .buttonStyle(CalmButtonStyle(tint: Theme.ember))
            Text("Feel a slow swell in your hands: in for four, out for six.")
                .font(.subheadline)
                .foregroundStyle(Theme.ember.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Temples

    private var templeSection: some View {
        VStack(spacing: 14) {
            Text("Temple acupressure")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ember)
                .accessibilityAddTraits(.isHeader)
            Text("Rest your fingertips on a temple and hold a pad. Make slow, gentle circles. A soft pulse guides your breathing for 30 seconds each side.")
                .font(.subheadline)
                .foregroundStyle(Theme.ember.opacity(0.8))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                TemplePad(title: "Left temple")
                TemplePad(title: "Right temple")
            }
        }
    }

    // MARK: Noise

    private var noiseSection: some View {
        VStack(spacing: 14) {
            Text("Soft noise")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ember)
                .accessibilityAddTraits(.isHeader)
            Picker("Noise type", selection: $noiseKind) {
                ForEach(NoiseKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            Button {
                noiseOn.toggle()
                if noiseOn {
                    engine.startNoise(noiseKind, volume: Float(volume))
                } else {
                    engine.stopNoise()
                }
            } label: {
                Label(noiseOn ? "Stop noise" : "Play \(noiseKind.title.lowercased())",
                      systemImage: noiseOn ? "speaker.slash.fill" : "speaker.wave.1.fill")
            }
            .buttonStyle(CalmButtonStyle(tint: Theme.ember))
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").foregroundStyle(Theme.ember).accessibilityHidden(true)
                Slider(value: $volume, in: 0.05...0.8)
                    .tint(Theme.ember)
                    .accessibilityLabel("Noise volume")
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.ember).accessibilityHidden(true)
            }
        }
        .onChange(of: noiseKind) { _, newKind in
            if noiseOn { engine.startNoise(newKind, volume: Float(volume)) }
        }
        .onChange(of: volume) { _, newVolume in
            if noiseOn { engine.setNoiseVolume(Float(newVolume)) }
        }
    }

    // MARK: Brightness

    private var dimSection: some View {
        VStack(spacing: 10) {
            Text("Screen brightness")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ember)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                Image(systemName: "sun.min.fill").foregroundStyle(Theme.ember).accessibilityHidden(true)
                Slider(value: $dimness, in: 0.02...0.4)
                    .tint(Theme.ember)
                    .accessibilityLabel("Screen brightness")
                Image(systemName: "sun.max.fill").foregroundStyle(Theme.ember).accessibilityHidden(true)
            }
            Text("Brightness returns to normal when you leave.")
                .font(.footnote)
                .foregroundStyle(Theme.ember.opacity(0.75))
        }
        .onChange(of: dimness) { _, newValue in
            dimmer.dim(to: CGFloat(newValue))
        }
    }
}

// MARK: - Orb

private struct OrbCanvas: View {
    let level: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: maxRadius * 0.18))
                for index in 0..<4 {
                    let f = CGFloat(index) / 3
                    let radius = maxRadius * (0.35 + 0.6 * f) * CGFloat(0.7 + 0.3 * level)
                    layer.fill(Draw.circle(center, radius), with: .color(Theme.ember.opacity(0.10 + 0.05 * level)))
                }
            }

            let core = maxRadius * CGFloat(0.28 + 0.12 * level)
            context.fill(
                Draw.circle(center, core),
                with: .radialGradient(
                    Gradient(colors: [Theme.ember.opacity(0.9), Theme.ember.opacity(0.35)]),
                    center: center,
                    startRadius: 0,
                    endRadius: core
                )
            )
        }
    }
}

// MARK: - Temple pad

/// Press and hold for 30 seconds. While held, a slow in-4, out-6 haptic pulse
/// guides breathing. VoiceOver users double-tap to start or stop the same
/// guided hold, so nobody needs to keep a finger down.
private struct TemplePad: View {
    let title: String
    @State private var pressing = false
    @State private var autoHold = false
    @State private var progress = 0.0
    @ScaledMetric(relativeTo: .body) private var ringWidth: CGFloat = 10

    private let engine = HapticAudioEngine.shared
    private var active: Bool { pressing || autoHold }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.ember.opacity(0.2), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.ember, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(Theme.ember.opacity(active ? 0.30 : 0.12))
                    .scaleEffect(0.72)
                Image(systemName: progress >= 1 ? "checkmark" : "hand.point.up.left.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.ember)
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 120, perform: {}, onPressingChanged: { pressing = $0 })
            .animation(.smooth, value: active)

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ember)
            Text(progress >= 1 ? "Done" : "\(Int(((1 - progress) * 30).rounded(.up))) seconds")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.ember.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) pad")
        .accessibilityValue(progress >= 1 ? "Done" : "\(Int(progress * 100)) percent")
        .accessibilityHint("Double tap to start or stop a 30 second guided hold")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { autoHold.toggle() }
        .task(id: active) { await runHold() }
    }

    private func runHold() async {
        guard active else {
            engine.stopHaptics()
            return
        }
        if progress >= 1 { progress = 0 }
        var clock = 0.0
        var exhaleStarted = false
        engine.breath(.inhale, duration: 4)
        while progress < 1 {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { break }
            clock += 0.1
            progress = min(1, progress + 0.1 / 30)
            if !exhaleStarted && clock >= 4 {
                engine.breath(.exhale, duration: 6)
                exhaleStarted = true
            }
            if clock >= 10 {
                clock = 0
                exhaleStarted = false
                engine.breath(.inhale, duration: 4)
            }
        }
        if Task.isCancelled {
            engine.stopHaptics()
        } else if progress >= 1 {
            engine.stopHaptics()
            engine.cue(.success)
            engine.chime(.complete)
            autoHold = false
        }
    }
}
