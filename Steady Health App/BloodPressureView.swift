import SwiftUI

// Blood pressure: a 60-second resonant breathing session (4.5 s in, 5.5 s out,
// six breaths) with heartbeat-like haptics, a three-step posture check, and an
// illustrative before/after pulse wave. It never measures anything.

struct BloodPressureView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = BreathingSession()

    private let palette = CareModule.bloodPressure.palette
    private let engine = HapticAudioEngine.shared

    var body: some View {
        ModuleScaffold(module: .bloodPressure) {
            pacerPanel
            readinessPanel
            wavePanel
            SafetyNote(text: "This is a calming routine, not a blood pressure measurement. Take your reading as your clinician and cuff instructions describe, and seek urgent help for chest pain, severe headache or sudden weakness.")
        }
        .onChange(of: session.state) { _, newValue in
            if newValue == .finished { state.finishCalmSession() }
        }
        .onDisappear { session.stop() }
    }

    // MARK: Pacer

    private var pacerPanel: some View {
        CalmPanel(palette: palette, title: "60-second calm-down", symbol: "heart.circle.fill") {
            TimelineView(.animation(paused: reduceMotion && session.state != .running)) { context in
                let snap = session.snapshot(at: context.date, idleLevel: 0.5)
                VStack(spacing: 12) {
                    RippleCanvas(
                        level: snap.level,
                        time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate,
                        running: session.state == .running,
                        palette: palette
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityElement()
                    .accessibilityLabel("Ripple rings that grow as you breathe in and shrink as you breathe out")

                    VStack(spacing: 4) {
                        switch session.state {
                        case .idle:
                            Text("Six slow breaths")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(palette.deep)
                            Text("Feel a soft heartbeat in your hands: it quickens as you breathe in and settles as you breathe out.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSoft)
                        case .running:
                            Text(snap.phase?.title ?? "")
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(palette.deep)
                            Text("\(snap.secondsLeftInSession) seconds left")
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                            ProgressView(value: min(1, max(0, snap.sessionProgress)))
                                .tint(palette.deep)
                                .accessibilityLabel("Session progress")
                        case .finished:
                            Text("Beautifully done")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(palette.deep)
                            Text("Stay seated and still for a moment before your reading.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                }
            }

            if session.state == .running {
                Button("Stop") { session.stop() }
                    .buttonStyle(CalmButtonStyle(tint: palette.deep, prominent: false))
            } else {
                Button {
                    engine.cue(.soft)
                    session.start(BreathPlan.resonant(cycles: 6))
                } label: {
                    Label(session.state == .finished ? "Go again" : "Start 60 seconds", systemImage: "play.fill")
                }
                .buttonStyle(CalmButtonStyle(tint: palette.deep))
            }
        }
    }

    // MARK: Readiness

    private var readinessPanel: some View {
        CalmPanel(palette: palette, title: "Ready for your reading?", symbol: "checkmark.seal.fill") {
            ForEach(PostureStep.allCases) { step in
                PostureRow(step: step, isChecked: state.postureChecked.contains(step), palette: palette) {
                    state.togglePosture(step)
                    if state.postureChecked.count == PostureStep.allCases.count {
                        engine.cue(.success)
                        engine.chime(.complete)
                    } else {
                        engine.cue(.selection)
                    }
                }
            }
            Text(state.postureChecked.count == PostureStep.allCases.count
                 ? "Ready. Rest for a moment, then take your reading."
                 : "\(state.postureChecked.count) of 3 checked")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.deep)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Before and after

    private var wavePanel: some View {
        CalmPanel(palette: palette, title: "Before and after", symbol: "waveform.path.ecg") {
            Text("An illustration of how a calmer rhythm can look. It is a simulation, not your data.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)

            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                VStack(alignment: .leading, spacing: 14) {
                    traceBlock(title: "Before the calm session (example)", time: time, bpm: 94, amplitude: 1.0, irregularity: 1.0, color: Theme.resting)
                    ZStack {
                        traceBlock(title: "After the calm session (example)", time: time, bpm: 66, amplitude: 0.72, irregularity: 0, color: Theme.ready)
                            .blur(radius: state.hasCompletedCalmSession ? 0 : 10)
                        if !state.hasCompletedCalmSession {
                            Label("Finish the 60-second session to reveal", systemImage: "lock.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.deep)
                                .padding(10)
                                .background(Capsule().fill(Theme.surface))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(state.hasCompletedCalmSession
                                        ? "After the calm session, example trace: slower and smoother"
                                        : "After trace locked until you finish the 60 second session")
                }
            }
        }
    }

    private func traceBlock(title: String, time: Double, bpm: Double, amplitude: Double, irregularity: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Canvas { context, size in
                Self.drawTrace(&context, size: size, time: time, bpm: bpm, amplitude: amplitude, irregularity: irregularity, color: color)
            }
            .aspectRatio(4, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .accessibilityHidden(true)
        }
    }

    /// A stylised arterial pulse: sharp systolic rise, small dicrotic notch.
    private static func arterial(_ p: Double) -> Double {
        let systolic = exp(-pow((p - 0.14) / 0.06, 2))
        let notch = 0.30 * exp(-pow((p - 0.42) / 0.07, 2))
        let tail = 0.18 * exp(-pow((p - 0.28) / 0.12, 2))
        return systolic + notch + tail
    }

    private static func drawTrace(
        _ context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        bpm: Double,
        amplitude: Double,
        irregularity: Double,
        color: Color
    ) {
        let w = size.width
        let h = size.height
        let window = 4.0 // seconds of signal across the width
        var path = Path()
        var x: CGFloat = 0
        var first = true
        while x <= w {
            let t = Double(x / w) * window + time * 1.2
            let warp = irregularity * sin(t * 6.1) * 0.05
            let beats = t * bpm / 60 + warp
            let phase = beats - floor(beats)
            let y = h * 0.86 - h * 0.7 * CGFloat(amplitude * arterial(phase))
            if first {
                path.move(to: CGPoint(x: x, y: y))
                first = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            x += 2
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(2, h * 0.035), lineCap: .round, lineJoin: .round))
    }
}

private struct PostureRow: View {
    let step: PostureStep
    let isChecked: Bool
    let palette: ModulePalette
    let action: () -> Void
    @Environment(\.highFocus) private var highFocus
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 64

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: step.symbol)
                    .font(.title2)
                    .foregroundStyle(palette.deep)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if !highFocus {
                        Text(step.detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isChecked ? Theme.ready : Theme.inkSoft)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: highFocus ? minHeight * 1.4 : minHeight, alignment: .leading)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(isChecked ? Theme.ready.opacity(0.6) : palette.deep.opacity(0.2), lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
        .accessibilityHint(step.detail)
        .accessibilityAddTraits(isChecked ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Ripple rings

private struct RippleCanvas: View {
    let level: Double
    let time: Double
    let running: Bool
    let palette: ModulePalette

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2
            let swell = CGFloat(0.72 + 0.28 * level)

            // Resting rings that expand and contract with the breath.
            let ringCount = 5
            for index in 0..<ringCount {
                let f = CGFloat(index + 1) / CGFloat(ringCount)
                let radius = maxRadius * (0.18 + 0.78 * f) * swell
                let opacity = 0.55 - 0.4 * Double(f) + 0.2 * level
                context.stroke(
                    Draw.circle(center, radius),
                    with: .color(palette.mid.opacity(max(0.08, opacity))),
                    lineWidth: max(2, maxRadius * 0.03 * (1.2 - f * 0.6))
                )
            }

            // Ripples drifting outward, like a pebble in still water.
            for index in 0..<3 {
                let phase = Draw.fract(time * 0.25 + Double(index) / 3)
                let radius = maxRadius * CGFloat(0.2 + 0.8 * phase) * swell
                context.stroke(
                    Draw.circle(center, radius),
                    with: .color(palette.deep.opacity((1 - phase) * 0.3)),
                    lineWidth: maxRadius * 0.015
                )
            }

            // Heart that gives a small beat while a session runs.
            let beat = running ? pow(max(0, sin(time * 2 * Double.pi * 1.1)), 6) : 0
            let orbRadius = maxRadius * CGFloat(0.17 + 0.07 * level + 0.02 * beat)
            context.fill(
                Draw.circle(center, orbRadius),
                with: .radialGradient(
                    Gradient(colors: [palette.mid, palette.deep]),
                    center: center,
                    startRadius: 0,
                    endRadius: orbRadius
                )
            )
            var heart = context.resolve(Image(systemName: "heart.fill"))
            heart.shading = .color(Theme.onAccent)
            let natural = heart.size
            let scale = (orbRadius * 1.0) / max(natural.width, natural.height)
            let heartSize = CGSize(width: natural.width * scale, height: natural.height * scale)
            context.draw(heart, in: CGRect(
                x: center.x - heartSize.width / 2,
                y: center.y - heartSize.height / 2,
                width: heartSize.width,
                height: heartSize.height
            ))
        }
    }
}
