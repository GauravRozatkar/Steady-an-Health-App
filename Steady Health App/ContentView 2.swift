import SwiftUI

// MARK: - App entry
// A single observable AppState is injected at the root. Every screen reads it
// from the environment, so there is no singleton state and no login.

@main
struct CalmAndSteadyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            DashboardView(showSettings: $showSettings)
                .navigationDestination(for: CareModule.self) { module in
                    switch module {
                    case .asthma: AsthmaView()
                    case .bloodPressure: BloodPressureView()
                    case .diabetes: DiabetesView()
                    case .migraine: MigraineView()
                    case .anxiety: AnxietyGroundingView()
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        // One flag drives larger targets and calmer layouts everywhere.
        .environment(\.highFocus, state.highFocusMode)
        .task {
            HapticAudioEngine.shared.prepare()
        }
    }
}

// MARK: - Home hub

struct DashboardView: View {
    @Environment(AppState.self) private var state
    @Environment(\.highFocus) private var highFocus
    @Binding var showSettings: Bool
    // Scaled so cards get wider as text gets larger, which keeps lines readable.
    @ScaledMetric(relativeTo: .body) private var cardMinimum: CGFloat = 300

    private var columns: [GridItem] {
        highFocus
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: cardMinimum), spacing: 16)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                welcome
                if state.demoMode && !highFocus {
                    FamilyStrip()
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(CareModule.allCases) { module in
                        NavigationLink(value: module) {
                            ModuleCard(module: module)
                        }
                        .buttonStyle(.plain)
                    }
                }
                comfortControls
                SafetyNote(text: "Calm and Steady offers comfort and routines only. It does not diagnose, measure or treat anything. In an emergency, call your local emergency number.")
            }
            .padding()
            .readableColumn(maxWidth: 1000)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Calm & Steady")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Label("Comfort settings", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Take a breath. You are not alone.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.ink)
            if !highFocus {
                Text("Pick whatever feels closest to right now. Everything works offline, with no sign-in.")
                    .font(.title3)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var demoBinding: Binding<Bool> {
        Binding(get: { state.demoMode }, set: { state.setDemoMode($0) })
    }

    private var focusBinding: Binding<Bool> {
        Binding(get: { state.highFocusMode }, set: { state.highFocusMode = $0 })
    }

    private var comfortControls: some View {
        // ViewThatFits picks side by side when there is room, stacked otherwise.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ToggleCard(title: "Family Demo Mode", detail: "Sample states for Dad, Mom and Wife", symbol: "person.3.fill", isOn: demoBinding)
                ToggleCard(title: "High-Focus Calm Mode", detail: "Bigger targets, less clutter", symbol: "scope", isOn: focusBinding)
            }
            VStack(spacing: 12) {
                ToggleCard(title: "Family Demo Mode", detail: "Sample states for Dad, Mom and Wife", symbol: "person.3.fill", isOn: demoBinding)
                ToggleCard(title: "High-Focus Calm Mode", detail: "Bigger targets, less clutter", symbol: "scope", isOn: focusBinding)
            }
        }
    }
}

private struct ToggleCard: View {
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool
    @Environment(\.highFocus) private var highFocus

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if !highFocus {
                        Text(detail).font(.footnote).foregroundStyle(Theme.inkSoft)
                    }
                }
            } icon: {
                Image(systemName: symbol)
            }
        }
        .padding(highFocus ? 20 : 14)
        .frame(maxWidth: .infinity)
        .background(shape.fill(Theme.surface))
        .overlay(shape.strokeBorder(Theme.ink.opacity(0.08), lineWidth: 1))
        .accessibilityHint(detail)
    }
}

struct ModuleCard: View {
    let module: CareModule
    @Environment(AppState.self) private var state
    @Environment(\.highFocus) private var highFocus
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 96

    var body: some View {
        let palette = module.palette
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        HStack(spacing: 16) {
            Image(systemName: module.symbol)
                .font(.title)
                .foregroundStyle(Theme.onAccent)
                .padding(14)
                .background(Circle().fill(palette.deep))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(module.title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(palette.deep)
                Text(module.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                if !highFocus, let status = state.demoStatus(for: module) {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .foregroundStyle(palette.deep)
                .accessibilityHidden(true)
        }
        .padding(highFocus ? 24 : 18)
        .frame(maxWidth: .infinity, minHeight: highFocus ? minHeight * 1.3 : minHeight, alignment: .leading)
        .background(shape.fill(palette.soft))
        .overlay(shape.strokeBorder(palette.deep.opacity(0.15), lineWidth: 1))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(module.title)")
    }
}

private struct FamilyStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Family demo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FamilyChip(name: "Dad", module: .diabetes)
                    FamilyChip(name: "Mom", module: .bloodPressure)
                    FamilyChip(name: "Wife", module: .asthma)
                }
            }
        }
    }
}

private struct FamilyChip: View {
    let name: String
    let module: CareModule
    @Environment(AppState.self) private var state

    var body: some View {
        let palette = module.palette
        NavigationLink(value: module) {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .foregroundStyle(palette.deep)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(Theme.ink)
                    Text(state.demoStatus(for: module) ?? module.title)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(Capsule().fill(palette.soft))
            .overlay(Capsule().strokeBorder(palette.deep.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("High-Focus Calm Mode", isOn: Binding(
                        get: { state.highFocusMode },
                        set: { state.highFocusMode = $0 }
                    ))
                    Toggle("Sound and chimes", isOn: Binding(
                        get: { state.soundEnabled },
                        set: { state.setSound($0) }
                    ))
                    Toggle("Haptics", isOn: Binding(
                        get: { state.hapticsEnabled },
                        set: { state.setHaptics($0) }
                    ))
                } header: {
                    Text("Comfort")
                } footer: {
                    Text(HapticAudioEngine.shared.supportsHaptics
                         ? "Rich haptics are available on this device."
                         : "Rich haptics are not available here, so gentle standard feedback is used where possible.")
                }

                Section("Demo") {
                    Toggle("Family Demo Mode", isOn: Binding(
                        get: { state.demoMode },
                        set: { state.setDemoMode($0) }
                    ))
                    Text("Loads sample states for Dad, Mom and Wife so every screen can be explored in a minute.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About and privacy") {
                    Label("Works fully offline. No accounts, no network, no tracking.", systemImage: "wifi.slash")
                    Label("Nothing is saved to disk. What you enter stays in memory until you close the app.", systemImage: "lock.fill")
                    Label("Not a medical device. It does not replace your care team or emergency help.", systemImage: "cross.case.fill")
                }
                .font(.subheadline)
            }
            .navigationTitle("Comfort settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
