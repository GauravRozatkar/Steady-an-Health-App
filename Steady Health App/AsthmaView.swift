import SwiftUI

// Asthma: a paced spacer routine you can follow with eyes closed (haptics and
// chimes mark each phase), plus a tap-to-log trigger checklist.

struct AsthmaView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session = BreathingSession()
    @State private var puffs = 2
    @State private var lastTrigger: AsthmaTrigger?
    @ScaledMetric(relativeTo: .body) private var tileMinimum: CGFloat = 150

    private let palette = CareModule.asthma.palette
    private let engine = HapticAudioEngine.shared

    var body: some View {
        ModuleScaffold(module: .asthma) {
            spacerPanel
            triggerPanel
            SafetyNote(text: "This guide follows a common spacer routine. Always use the steps and doses from your own asthma action plan. If breathing is hard, you cannot speak in full sentences, or your reliever is not helping, call your local emergency number.")
        }
        .onDisappear {
            session.stop()
            engine.suspendAudio()
        }
    }

    // MARK: Spacer guide

    private var spacerPanel: some View {
        CalmPanel(palette: palette, title: "Spacer routine guide", symbol: "lungs.fill") {
            // TimelineView redraws every frame while the session runs, and the
            // lung is derived purely from the clock, so it never drifts.
            TimelineView(.animation(paused: reduceMotion && session.state != .running)) { context in
                let snap = session.snapshot(at: context.date)
                VStack(spacing: 14) {
                    LungCanvas(
                        level: snap.level,
                        time: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate,
                        palette: palette
                    )
                    .aspectRatio(1.1, contentMode: .fit)
                    .accessibilityElement()
                    .accessibilityLabel("Breathing animation. The lungs grow as you breathe in and shrink as you breathe out.")

                    phaseReadout(snap)
                }
            }
            controls
        }
    }

    @ViewBuilder
    private func phaseReadout(_ snap: BreathSnapshot) -> some View {
        VStack(spacing: 6) {
            switch session.state {
            case .idle:
                Text("Ready when you are")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(palette.deep)
                Text("Chimes and gentle pulses tell you when to switch, so you can close your eyes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            case .running:
                if let phase = snap.phase {
                    Text(phase.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(palette.deep)
                    Text(phase.instruction)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                    Text("\(snap.secondsLeftInPhase)")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.ink)
                    ProgressView(value: min(1, max(0, snap.sessionProgress)))
                        .tint(palette.deep)
                        .accessibilityLabel("Session progress")
                }
            case .finished:
                Text("Well done")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(palette.deep)
                Text("Keep breathing easy and sit upright for a few minutes.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if session.state == .running {
                HStack(spacing: 12) {
                    Button("Skip step") { session.skipPhase() }
                        .buttonStyle(CalmButtonStyle(tint: palette.deep, prominent: false))
                    Button("Stop") { session.stop() }
                        .buttonStyle(CalmButtonStyle(tint: palette.deep))
                }
            } else {
                Stepper(value: $puffs, in: 1...3) {
                    Text("Puffs this session: \(puffs)")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                }
                Button {
                    engine.cue(.soft)
                    session.start(BreathPlan.spacer(puffs: puffs))
                } label: {
                    Label(session.state == .finished ? "Go again" : "Start spacer guide", systemImage: "play.fill")
                }
                .buttonStyle(CalmButtonStyle(tint: palette.deep))
            }
        }
    }

    // MARK: Triggers

    private var triggerPanel: some View {
        CalmPanel(palette: palette, title: "What set it off?", symbol: "checklist") {
            Text("Tap what you notice. It is a private note for you and never leaves this device.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimum), spacing: 12)], spacing: 12) {
                ForEach(AsthmaTrigger.allCases) { trigger in
                    TriggerTile(trigger: trigger, count: state.triggerCountToday(trigger), palette: palette) {
                        log(trigger)
                    }
                }
            }

            if let trigger = lastTrigger {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(palette.deep)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A little comfort for \(trigger.title.lowercased())")
                            .font(.headline)
                            .foregroundStyle(palette.deep)
                        Text(trigger.tip)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
                .accessibilityElement(children: .combine)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            recentLog
        }
    }

    @ViewBuilder
    private var recentLog: some View {
        let recent = Array(state.triggerLog.suffix(3).reversed())
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                ForEach(recent) { entry in
                    HStack {
                        Label(entry.trigger.title, systemImage: entry.trigger.symbol)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(entry.date, style: .relative) ago")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func log(_ trigger: AsthmaTrigger) {
        state.logTrigger(trigger)
        engine.cue(.tap)
        engine.chime(.step(AsthmaTrigger.allCases.firstIndex(of: trigger) ?? 0))
        withAnimation(.smooth) { lastTrigger = trigger }
        AccessibilityNotification.Announcement("Logged \(trigger.title). \(trigger.tip)").post()
    }
}

private struct TriggerTile: View {
    let trigger: AsthmaTrigger
    let count: Int
    let palette: ModulePalette
    let action: () -> Void
    @Environment(\.highFocus) private var highFocus
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 96

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: trigger.symbol)
                    .font(.title)
                    .foregroundStyle(palette.deep)
                Text(trigger.title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.ink)
                if count > 0 {
                    Text("\(count) today")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .foregroundStyle(Theme.onAccent)
                        .background(Capsule().fill(palette.deep))
                }
            }
            .frame(maxWidth: .infinity, minHeight: highFocus ? minHeight * 1.4 : minHeight)
            .padding(10)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(palette.deep.opacity(0.25), lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trigger.title), logged \(count) times today")
        .accessibilityHint("Double tap to log this trigger and hear a comfort tip")
    }
}

// MARK: - Lung illustration
// Pure Canvas drawing with coordinates relative to the canvas size, so it
// scales from a phone to a Mac window without any fixed frames.

private struct LungCanvas: View {
    let level: Double
    let time: Double
    let palette: ModulePalette

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w / 2, y: h * 0.44)
            let lungHeight = h * 0.56 * CGFloat(0.82 + 0.18 * level)
            let lobeWidth = w * 0.27 * CGFloat(0.84 + 0.16 * level)
            let gap = w * 0.015
            let top = center.y - lungHeight / 2

            // Soft glow that swells with each breath.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: w * 0.06))
                let glow = CGRect(x: center.x - w * 0.34, y: top - lungHeight * 0.05, width: w * 0.68, height: lungHeight * 1.1)
                layer.fill(Path(ellipseIn: glow), with: .color(palette.mid.opacity(0.22 + 0.25 * level)))
            }

            // Gently moving waves under the lungs.
            for index in 0..<3 {
                let order = Double(index)
                let amplitude = h * CGFloat(0.012 + 0.03 * level) * CGFloat(1 + order * 0.5)
                let baseline = h * CGFloat(0.82 - 0.07 * level + 0.045 * order)
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: h))
                var x: CGFloat = 0
                while x <= w {
                    let along = Double(x / w) * 2 * Double.pi
                    let phase = along * (1.1 + 0.35 * order) + time * (0.7 + 0.25 * order)
                    wave.addLine(to: CGPoint(x: x, y: baseline + amplitude * CGFloat(sin(phase))))
                    x += 4
                }
                wave.addLine(to: CGPoint(x: w, y: h))
                wave.closeSubpath()
                context.fill(wave, with: .color(palette.mid.opacity(0.16 + 0.07 * order)))
            }

            // Two organic lobes, drawn from one unit shape and mirrored.
            let unit = Self.lobe()
            let right = unit.applying(CGAffineTransform(a: lobeWidth, b: 0, c: 0, d: lungHeight, tx: center.x + gap, ty: top))
            let left = unit.applying(CGAffineTransform(a: -lobeWidth, b: 0, c: 0, d: lungHeight, tx: center.x - gap, ty: top))
            let fill = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [palette.mid.opacity(0.55), palette.mid.opacity(0.9)]),
                startPoint: CGPoint(x: center.x, y: top),
                endPoint: CGPoint(x: center.x, y: top + lungHeight)
            )
            for lobe in [left, right] {
                context.fill(lobe, with: fill)
                context.stroke(lobe, with: .color(palette.deep), lineWidth: max(1.5, w * 0.006))
            }

            // Windpipe and bronchi.
            var airway = Path()
            let windpipeTop = CGPoint(x: center.x, y: top - lungHeight * 0.1)
            let fork = CGPoint(x: center.x, y: top + lungHeight * 0.26)
            airway.move(to: windpipeTop)
            airway.addLine(to: fork)
            for side in [-1.0, 1.0] {
                let s = CGFloat(side)
                airway.move(to: fork)
                airway.addCurve(
                    to: CGPoint(x: center.x + s * lobeWidth * 0.55, y: top + lungHeight * 0.62),
                    control1: CGPoint(x: center.x + s * lobeWidth * 0.1, y: top + lungHeight * 0.38),
                    control2: CGPoint(x: center.x + s * lobeWidth * 0.5, y: top + lungHeight * 0.4)
                )
            }
            context.stroke(airway, with: .color(palette.deep), style: StrokeStyle(lineWidth: max(2, w * 0.014), lineCap: .round, lineJoin: .round))

            // Tiny air sacs that open as you breathe in.
            for index in 0..<14 {
                let i = Double(index)
                let ux = 0.25 + 0.55 * Draw.fract(i * 0.618)
                let uy = 0.2 + 0.65 * Draw.fract(i * 0.381 + 0.2)
                let pulse = 0.6 + 0.8 * level + 0.2 * sin(time * 2 + i)
                let radius = w * 0.009 * CGFloat(max(0.2, pulse))
                for side in [-1.0, 1.0] {
                    let point = CGPoint(
                        x: center.x + CGFloat(side) * (gap + lobeWidth * CGFloat(ux)),
                        y: top + lungHeight * CGFloat(uy)
                    )
                    context.fill(Draw.circle(point, radius), with: .color(Theme.surface.opacity(0.55)))
                }
            }
        }
    }

    /// One lobe in a unit box. x runs from the windpipe outward, y from top to bottom.
    private static func lobe() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0.05, y: 0.02))
        path.addCurve(to: CGPoint(x: 0.95, y: 0.55), control1: CGPoint(x: 0.55, y: -0.05), control2: CGPoint(x: 1.05, y: 0.2))
        path.addCurve(to: CGPoint(x: 0.62, y: 1.0), control1: CGPoint(x: 0.9, y: 0.85), control2: CGPoint(x: 0.85, y: 1.0))
        path.addCurve(to: CGPoint(x: 0.05, y: 0.85), control1: CGPoint(x: 0.4, y: 1.0), control2: CGPoint(x: 0.15, y: 0.98))
        path.addCurve(to: CGPoint(x: 0.05, y: 0.02), control1: CGPoint(x: -0.02, y: 0.6), control2: CGPoint(x: -0.05, y: 0.25))
        path.closeSubpath()
        return path
    }
}
