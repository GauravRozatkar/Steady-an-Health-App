import SwiftUI

// Anxiety and panic: a 5-4-3-2-1 grounding journey. Each sensory anchor is a
// frosted-glass card that physically "clears away" when tapped, with a haptic
// swish-and-pop and a rising pentatonic chime. Steps advance on their own, so
// the person only ever has one simple thing to do: tap.

struct AnxietyGroundingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.highFocus) private var highFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false
    @State private var stepIndex = 0
    @State private var cleared: Set<Int> = []
    @State private var isFinished = false
    @ScaledMetric(relativeTo: .body) private var cardMinimum: CGFloat = 150

    private let palette = CareModule.anxiety.palette
    private let engine = HapticAudioEngine.shared
    private let steps = GroundingStep.all

    private var step: GroundingStep { steps[stepIndex] }

    private var columns: [GridItem] {
        highFocus
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: cardMinimum), spacing: 14)]
    }

    var body: some View {
        ModuleScaffold(module: .anxiety) {
            if isFinished {
                finishedPanel
            } else if started {
                journeyPanel
            } else {
                introPanel
            }
            SafetyNote(text: "Grounding can ease intense moments, but it is not a treatment. If you feel unsafe or in crisis, contact your local emergency number or a trusted person right now.")
        }
    }

    // MARK: Intro

    private var introPanel: some View {
        CalmPanel(palette: palette, title: "You are safe to slow down", symbol: "hands.sparkles.fill") {
            Text("We will find five things you can see, four you can touch, three you can hear, two you can smell and one you can taste. Tap each frosted card once you have noticed it.")
                .font(.body)
                .foregroundStyle(Theme.ink)
            Button {
                engine.cue(.soft)
                engine.chime(.inhale)
                withAnimation(.smooth) { started = true }
            } label: {
                Label("Begin", systemImage: "play.fill")
            }
            .buttonStyle(CalmButtonStyle(tint: palette.deep))
        }
    }

    // MARK: Journey

    private var journeyPanel: some View {
        CalmPanel(palette: palette) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(stepIndex + 1) of \(steps.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                ProgressView(value: Double(stepIndex), total: Double(steps.count))
                    .tint(palette.deep)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(step.count)")
                    .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                    .foregroundStyle(palette.deep)
                Text(step.headline.dropFirst(2))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Name \(step.headline)")
            .accessibilityAddTraits(.isHeader)

            Text("Tap a card as you notice each one. Take your time.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(step.prompts.enumerated()), id: \.offset) { index, prompt in
                    FrostedCard(
                        prompt: prompt,
                        symbol: step.symbol,
                        index: index,
                        total: step.prompts.count,
                        isCleared: cleared.contains(index),
                        reduceMotion: reduceMotion,
                        palette: palette
                    ) {
                        clear(index)
                    }
                }
            }
            // A new identity per step lets the whole group cross-fade.
            .id(stepIndex)
            .transition(.opacity)

            HStack(spacing: 12) {
                Button("Skip this step") { advance() }
                    .buttonStyle(CalmButtonStyle(tint: palette.deep, prominent: false))
                Button("Start over") { reset() }
                    .buttonStyle(CalmButtonStyle(tint: palette.deep, prominent: false))
            }
        }
    }

    private func clear(_ index: Int) {
        guard !cleared.contains(index) else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.7)) {
            _ = cleared.insert(index)
        }
        engine.cue(.clear(step: cleared.count))
        // The pitch climbs across the whole journey, a quiet sense of progress.
        engine.chime(.step(stepIndex * 2 + cleared.count))

        if cleared.count == step.prompts.count {
            let current = stepIndex
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1100))
                guard current == stepIndex, !isFinished, started else { return }
                advance()
            }
        }
    }

    private func advance() {
        if stepIndex < steps.count - 1 {
            withAnimation(.smooth) {
                stepIndex += 1
                cleared = []
            }
            AccessibilityNotification.Announcement("Next: \(steps[stepIndex].headline)").post()
        } else {
            withAnimation(.smooth) { isFinished = true }
            state.groundingSessions += 1
            engine.cue(.success)
            engine.chime(.complete)
            AccessibilityNotification.Announcement("You did it. You are here, in this moment.").post()
        }
    }

    private func reset() {
        engine.cue(.soft)
        withAnimation(.smooth) {
            stepIndex = 0
            cleared = []
            isFinished = false
            started = false
        }
    }

    // MARK: Finished

    private var finishedPanel: some View {
        CalmPanel(palette: palette, title: "You are here", symbol: "checkmark.seal.fill") {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                CalmRing(time: time, palette: palette)
                    .aspectRatio(1.6, contentMode: .fit)
                    .accessibilityHidden(true)
            }
            Text("You noticed all fifteen anchors. This moment is steady and you are in it. Take one slow breath in, and let it out for a little longer.")
                .font(.body)
                .foregroundStyle(Theme.ink)
            Button {
                reset()
            } label: {
                Label("Go again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(CalmButtonStyle(tint: palette.deep))
        }
    }
}

// MARK: - Frosted glass card

private struct FrostedCard: View {
    let prompt: String
    let symbol: String
    let index: Int
    let total: Int
    let isCleared: Bool
    let reduceMotion: Bool
    let palette: ModulePalette
    let action: () -> Void

    @Environment(\.highFocus) private var highFocus
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 120

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        Button(action: action) {
            ZStack {
                // The calm scene revealed once the frost is gone.
                shape.fill(LinearGradient(
                    colors: [palette.mid.opacity(0.55), palette.soft],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                VStack(spacing: 8) {
                    Image(systemName: isCleared ? "checkmark.circle.fill" : symbol)
                        .font(.largeTitle)
                        .foregroundStyle(palette.deep)
                    Text(isCleared ? "Noticed" : "")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.deep)
                }

                // The frost: material, a white sheen, and tiny ice speckles.
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    Canvas { context, size in
                        for dot in 0..<46 {
                            let i = Double(dot)
                            let x = Draw.fract(i * 0.6180339) * size.width
                            let y = Draw.fract(i * 0.7548776 + 0.3) * size.height
                            let radius = size.width * CGFloat(0.006 + 0.01 * Draw.fract(i * 0.317))
                            context.fill(Draw.circle(CGPoint(x: x, y: y), radius), with: .color(.white.opacity(0.4)))
                        }
                    }
                    .clipShape(shape)
                    Text(prompt)
                        .font(.system(.headline, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                }
                // Clearing animation: blur away and drift outward. With
                // Reduce Motion on, it simply fades.
                .blur(radius: isCleared && !reduceMotion ? 22 : 0)
                .scaleEffect(isCleared && !reduceMotion ? 1.12 : 1)
                .opacity(isCleared ? 0 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: highFocus ? minHeight * 1.4 : minHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(palette.deep.opacity(isCleared ? 0.35 : 0.2), lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(isCleared)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card \(index + 1) of \(total): \(prompt)")
        .accessibilityValue(isCleared ? "Noticed" : "Not yet noticed")
        .accessibilityHint(isCleared ? "" : "Double tap once you have noticed it")
    }
}

// MARK: - Finished ring

private struct CalmRing: View {
    let time: Double
    let palette: ModulePalette

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2
            // A slow ten-second breath: four seconds in, six out, as a smooth wave.
            let breath = 0.5 + 0.5 * sin(time * 2 * Double.pi / 10 - Double.pi / 2)
            for index in 0..<4 {
                let f = CGFloat(index) / 3
                let radius = maxRadius * (0.35 + 0.55 * f) * CGFloat(0.8 + 0.2 * breath)
                context.stroke(
                    Draw.circle(center, radius),
                    with: .color(palette.mid.opacity(0.5 - 0.1 * Double(index))),
                    lineWidth: maxRadius * 0.04
                )
            }
            let core = maxRadius * CGFloat(0.22 + 0.06 * breath)
            context.fill(
                Draw.circle(center, core),
                with: .radialGradient(
                    Gradient(colors: [palette.mid, palette.deep]),
                    center: center,
                    startRadius: 0,
                    endRadius: core
                )
            )
        }
    }
}
