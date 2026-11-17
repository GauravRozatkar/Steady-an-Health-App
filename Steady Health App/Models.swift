import SwiftUI

// MARK: - Modules

enum CareModule: String, CaseIterable, Identifiable, Hashable {
    case asthma, bloodPressure, diabetes, migraine, anxiety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asthma: "Asthma"
        case .bloodPressure: "Blood Pressure"
        case .diabetes: "Diabetes"
        case .migraine: "Migraine and Overload"
        case .anxiety: "Anxiety and Panic"
        }
    }

    var subtitle: String {
        switch self {
        case .asthma: "Paced breathing and spacer timer"
        case .bloodPressure: "60-second calm-down session"
        case .diabetes: "Plate builder and site rotation"
        case .migraine: "Low-stimulus relief sanctuary"
        case .anxiety: "5-4-3-2-1 grounding journey"
        }
    }

    var tagline: String {
        switch self {
        case .asthma: "For when breathing needs to slow down and feel easier."
        case .bloodPressure: "A quiet minute before a cuff reading."
        case .diabetes: "Gentle meals and kinder rotation of sites."
        case .migraine: "Light, sound and motion turned right down."
        case .anxiety: "Come back to the room, one sense at a time."
        }
    }

    var symbol: String {
        switch self {
        case .asthma: "lungs.fill"
        case .bloodPressure: "waveform.path.ecg"
        case .diabetes: "drop.fill"
        case .migraine: "moon.stars.fill"
        case .anxiety: "hands.sparkles.fill"
        }
    }
}

// MARK: - Breathing

struct BreathPhase: Identifiable, Equatable {
    let id = UUID()
    var kind: BreathKind
    var title: String
    var instruction: String
    var duration: TimeInterval
    /// Lung fullness at the start and end of the phase, 0 (empty) to 1 (full).
    var from: Double
    var to: Double
    var heartbeat = false
    var chime: Chime? = nil

    static func == (lhs: BreathPhase, rhs: BreathPhase) -> Bool { lhs.id == rhs.id }
}

enum BreathPlan {
    /// Metered-dose inhaler with spacer: breathe out, press and inhale slowly
    /// for 5 seconds, hold for 10, breathe out slowly. Rests between puffs.
    static func spacer(puffs: Int) -> [BreathPhase] {
        var phases: [BreathPhase] = []
        let count = max(1, puffs)
        for puff in 1...count {
            phases.append(BreathPhase(kind: .exhale, title: "Breathe out", instruction: "Empty your lungs gently.", duration: 4, from: 0.5, to: 0, chime: .exhale))
            phases.append(BreathPhase(kind: .inhale, title: "Press once, breathe in", instruction: "Press the inhaler into the spacer, then breathe in slowly.", duration: 5, from: 0, to: 1, chime: .inhale))
            phases.append(BreathPhase(kind: .hold, title: "Hold", instruction: "Hold your breath and count slowly.", duration: 10, from: 1, to: 1, chime: .hold))
            phases.append(BreathPhase(kind: .exhale, title: "Slow breath out", instruction: "Let the air out slowly.", duration: 5, from: 1, to: 0, chime: .exhale))
            if puff < count {
                phases.append(BreathPhase(kind: .rest, title: "Wait", instruction: "Rest for 30 seconds before the next puff, if your plan says so.", duration: 30, from: 0, to: 0.5))
            }
        }
        return phases
    }

    /// Resonant breathing: about six breaths a minute (4.5 s in, 5.5 s out).
    static func resonant(cycles: Int = 6) -> [BreathPhase] {
        var phases: [BreathPhase] = []
        for _ in 0..<cycles {
            phases.append(BreathPhase(kind: .inhale, title: "Breathe in", instruction: "Slowly through your nose.", duration: 4.5, from: 0, to: 1, heartbeat: true))
            phases.append(BreathPhase(kind: .exhale, title: "Breathe out", instruction: "Softly, a little longer.", duration: 5.5, from: 1, to: 0, heartbeat: true))
        }
        return phases
    }

    /// Slow 4 s in, 6 s out pulse for the migraine sanctuary. No chimes.
    static func slowPulse(cycles: Int = 30) -> [BreathPhase] {
        var phases: [BreathPhase] = []
        for _ in 0..<cycles {
            phases.append(BreathPhase(kind: .inhale, title: "In", instruction: "Let the pulse rise.", duration: 4, from: 0, to: 1))
            phases.append(BreathPhase(kind: .exhale, title: "Out", instruction: "Let it fade.", duration: 6, from: 1, to: 0))
        }
        return phases
    }
}

struct BreathSnapshot {
    var phase: BreathPhase?
    var level: Double
    var secondsLeftInPhase: Int
    var sessionProgress: Double
    var secondsLeftInSession: Int
}

/// Runs a list of phases. Visuals are derived from the clock (`snapshot(at:)`)
/// inside a TimelineView, so animation stays smooth and drift-free. Haptics
/// and chimes fire once per phase from the task below.
@MainActor
@Observable
final class BreathingSession {
    enum State { case idle, running, finished }

    private(set) var state: State = .idle
    private(set) var phases: [BreathPhase] = []
    private(set) var phaseIndex = 0
    private(set) var phaseStart = Date()

    private var cumulative: [TimeInterval] = []
    private var runner: Task<Void, Never>?
    private var skipRequested = false
    private var announces = true

    var totalDuration: TimeInterval { phases.reduce(0) { $0 + $1.duration } }

    func start(_ plan: [BreathPhase], announce: Bool = true) {
        stop()
        guard !plan.isEmpty else { return }
        phases = plan
        announces = announce
        var running: TimeInterval = 0
        cumulative = plan.map { phase in
            defer { running += phase.duration }
            return running
        }
        phaseIndex = 0
        phaseStart = Date()
        state = .running
        runner = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        runner?.cancel()
        runner = nil
        HapticAudioEngine.shared.stopHaptics()
        state = .idle
        phaseIndex = 0
    }

    func skipPhase() {
        skipRequested = true
    }

    private func run() async {
        let engine = HapticAudioEngine.shared
        for (index, phase) in phases.enumerated() {
            if Task.isCancelled { return }
            phaseIndex = index
            phaseStart = Date()
            skipRequested = false
            engine.breath(phase.kind, duration: phase.duration, heartbeat: phase.heartbeat)
            if let chime = phase.chime { engine.chime(chime) }
            if announces {
                // Spoken for VoiceOver users, and a second cue for everyone with eyes closed.
                AccessibilityNotification.Announcement("\(phase.title). \(phase.instruction)").post()
            }
            await wait(phase.duration)
        }
        guard !Task.isCancelled else { return }
        state = .finished
        engine.cue(.success)
        engine.chime(.complete)
    }

    private func wait(_ seconds: TimeInterval) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !skipRequested && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func snapshot(at date: Date, idleLevel: Double = 0.4) -> BreathSnapshot {
        switch state {
        case .idle:
            return BreathSnapshot(phase: nil, level: idleLevel, secondsLeftInPhase: 0, sessionProgress: 0, secondsLeftInSession: 0)
        case .finished:
            return BreathSnapshot(phase: nil, level: 0.3, secondsLeftInPhase: 0, sessionProgress: 1, secondsLeftInSession: 0)
        case .running:
            guard phases.indices.contains(phaseIndex), cumulative.indices.contains(phaseIndex) else {
                return BreathSnapshot(phase: nil, level: idleLevel, secondsLeftInPhase: 0, sessionProgress: 0, secondsLeftInSession: 0)
            }
            let phase = phases[phaseIndex]
            let elapsed = min(max(0, date.timeIntervalSince(phaseStart)), phase.duration)
            let fraction = elapsed / phase.duration
            let eased = (1 - cos(Double.pi * fraction)) / 2
            let level = phase.from + (phase.to - phase.from) * eased
            let done = cumulative[phaseIndex] + elapsed
            return BreathSnapshot(
                phase: phase,
                level: level,
                secondsLeftInPhase: Int((phase.duration - elapsed).rounded(.up)),
                sessionProgress: done / totalDuration,
                secondsLeftInSession: Int((totalDuration - done).rounded(.up))
            )
        }
    }
}

// MARK: - Asthma

enum AsthmaTrigger: String, CaseIterable, Identifiable {
    case dust, coldAir, pollen, stress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dust: "Dust"
        case .coldAir: "Cold air"
        case .pollen: "Pollen"
        case .stress: "Stress"
        }
    }

    var symbol: String {
        switch self {
        case .dust: "sun.dust.fill"
        case .coldAir: "snowflake"
        case .pollen: "camera.macro"
        case .stress: "brain.head.profile"
        }
    }

    /// Comfort tips only: non-clinical and safe for anyone.
    var tip: String {
        switch self {
        case .dust: "Step toward fresher air if you can and sip some water. A damp cloth on surfaces later can help."
        case .coldAir: "Loosely cover your nose and mouth with a scarf so the air is warmer when you breathe it."
        case .pollen: "Close windows for now, then rinse your face and hands with cool water."
        case .stress: "Drop your shoulders and unclench your jaw. Try the slow breathing guide above."
        }
    }
}

struct TriggerEntry: Identifiable {
    let id = UUID()
    let trigger: AsthmaTrigger
    let date: Date
}

// MARK: - Blood pressure

enum PostureStep: String, CaseIterable, Identifiable {
    case feet, back, arm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feet: "Feet flat on the floor"
        case .back: "Back supported"
        case .arm: "Arm at heart level"
        }
    }

    var detail: String {
        switch self {
        case .feet: "Uncross your legs and let your feet rest."
        case .back: "Sit back so the chair holds you."
        case .arm: "Rest your arm on a table, cuff level with your heart."
        }
    }

    var symbol: String {
        switch self {
        case .feet: "shoeprints.fill"
        case .back: "chair.lounge.fill"
        case .arm: "heart.fill"
        }
    }
}

// MARK: - Diabetes: plate

enum FoodGroup: String, CaseIterable, Identifiable {
    case veggies, protein, carbs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .veggies: "Fiber and veggies"
        case .protein: "Lean protein"
        case .carbs: "Complex carbs"
        }
    }

    var shareText: String {
        switch self {
        case .veggies: "Half the plate"
        case .protein, .carbs: "A quarter"
        }
    }

    /// Target share of the plate.
    var share: Double {
        switch self {
        case .veggies: 0.5
        case .protein, .carbs: 0.25
        }
    }

    /// Slots on the drawn plate, proportional to its sector.
    var capacity: Int {
        switch self {
        case .veggies: 8
        case .protein, .carbs: 4
        }
    }

    var symbol: String {
        switch self {
        case .veggies: "leaf.fill"
        case .protein: "fish.fill"
        case .carbs: "circle.grid.3x3.fill"
        }
    }

    var tint: Color {
        switch self {
        case .veggies: Color(hex: 0x4F8A5B)
        case .protein: Color(hex: 0xB9714A)
        case .carbs: Color(hex: 0xB28A2E)
        }
    }
}

struct FoodItem: Identifiable, Hashable {
    let name: String
    let group: FoodGroup
    let symbol: String
    let tintHex: UInt32
    /// Relative weights, 0 to 1, used by the illustrative curve model.
    let carbs: Double
    let fiber: Double
    let protein: Double

    var id: String { name }
    var tint: Color { Color(hex: tintHex) }

    static let catalog: [FoodItem] = [
        FoodItem(name: "Leafy greens", group: .veggies, symbol: "leaf.fill", tintHex: 0x3F7A4D, carbs: 0.10, fiber: 0.9, protein: 0.10),
        FoodItem(name: "Broccoli", group: .veggies, symbol: "tree.fill", tintHex: 0x36703F, carbs: 0.12, fiber: 0.9, protein: 0.15),
        FoodItem(name: "Carrots", group: .veggies, symbol: "carrot.fill", tintHex: 0xB8611C, carbs: 0.20, fiber: 0.8, protein: 0.05),
        FoodItem(name: "Tomatoes", group: .veggies, symbol: "seal.fill", tintHex: 0xB23B27, carbs: 0.12, fiber: 0.7, protein: 0.05),
        FoodItem(name: "Fish", group: .protein, symbol: "fish.fill", tintHex: 0x3F6F99, carbs: 0, fiber: 0, protein: 1.0),
        FoodItem(name: "Chicken", group: .protein, symbol: "bird.fill", tintHex: 0x9C6A2C, carbs: 0, fiber: 0, protein: 1.0),
        FoodItem(name: "Eggs", group: .protein, symbol: "oval.fill", tintHex: 0xA57A1F, carbs: 0, fiber: 0, protein: 0.9),
        FoodItem(name: "Beans", group: .protein, symbol: "oval.portrait.fill", tintHex: 0x7A4A36, carbs: 0.25, fiber: 0.6, protein: 0.7),
        FoodItem(name: "Brown rice", group: .carbs, symbol: "circle.grid.3x3.fill", tintHex: 0x8A7348, carbs: 0.8, fiber: 0.3, protein: 0.15),
        FoodItem(name: "Sweet potato", group: .carbs, symbol: "capsule.fill", tintHex: 0xB0572A, carbs: 0.75, fiber: 0.4, protein: 0.05),
        FoodItem(name: "Whole-grain bread", group: .carbs, symbol: "rectangle.roundedtop.fill", tintHex: 0x946828, carbs: 0.75, fiber: 0.35, protein: 0.15),
        FoodItem(name: "Oats", group: .carbs, symbol: "circle.grid.2x2.fill", tintHex: 0x8C7350, carbs: 0.7, fiber: 0.45, protein: 0.2)
    ]
}

/// One food on the plate. The id lets a tap remove exactly that token.
struct PlacedFood: Identifiable {
    let id = UUID()
    let item: FoodItem
}

/// Illustrative curve model. It shows the shape of "steady versus spiky" for
/// a given plate and deliberately uses no real glucose values.
enum GlucoseModel {
    static let baseline = 0.28
    static let ceiling = 1.25
    static let bandLow = 0.2
    static let bandHigh = 0.5

    static func amplitude(load: Double, fiber: Double, protein: Double) -> Double {
        0.62 * min(1.5, load) * (1 - 0.5 * fiber - 0.25 * protein)
    }

    static func value(atMinute minute: Double, load: Double, fiber: Double, protein: Double) -> Double {
        let amp = amplitude(load: load, fiber: fiber, protein: protein)
        let peakMinute = 45 + 35 * fiber + 15 * protein
        let x = max(0, minute) / peakMinute
        return baseline + amp * x * x * exp(2 * (1 - x))
    }
}

struct PlateAnalysis {
    let items: [FoodItem]

    var count: Int { items.count }

    func count(_ group: FoodGroup) -> Int {
        items.filter { $0.group == group }.count
    }

    func fraction(_ group: FoodGroup) -> Double {
        count == 0 ? 0 : Double(count(group)) / Double(count)
    }

    /// 1 means exactly half veggies, a quarter protein, a quarter carbs.
    var balance: Double {
        guard count > 0 else { return 0 }
        let distance = FoodGroup.allCases.reduce(0.0) { $0 + abs(fraction($1) - $1.share) }
        return max(0, 1 - distance / 2)
    }

    var load: Double { items.reduce(0) { $0 + $1.carbs } / 2 }
    var fiber: Double { min(1, items.reduce(0) { $0 + $1.fiber } / 3) }
    var protein: Double { min(1, items.reduce(0) { $0 + $1.protein } / 2) }

    var peak: Double {
        GlucoseModel.baseline + GlucoseModel.amplitude(load: load, fiber: fiber, protein: protein)
    }

    var verdict: String {
        if count == 0 { return "Add foods to see your curve" }
        if peak <= 0.48 { return "Steady and gentle" }
        if peak <= 0.66 { return "A gentle hill" }
        return "A tall, quick spike"
    }

    var verdictSymbol: String {
        if count == 0 { return "plus.circle" }
        if peak <= 0.48 { return "checkmark.circle.fill" }
        if peak <= 0.66 { return "arrow.up.right.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    var nudge: String {
        if count == 0 { return "Tap a food below to place it on the plate." }
        if balance > 0.85 { return "Lovely balance. This plate keeps things calm and steady." }
        if fraction(.veggies) < 0.4 { return "Try adding veggies: fiber slows the climb." }
        if fraction(.protein) < 0.18 { return "A little protein helps the curve stay smooth." }
        if fraction(.carbs) > 0.35 { return "Try fewer carbs, or swap one for veggies." }
        return "Nearly there. Small swaps will smooth it further."
    }
}

// MARK: - Diabetes: site rotation

enum SiteMapMode: String, CaseIterable, Identifiable {
    case injection, fingerPrick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .injection: "Injection sites"
        case .fingerPrick: "Fingertips"
        }
    }
}

enum SiteStatus {
    case ready, healing, resting

    var title: String {
        switch self {
        case .ready: "Ready"
        case .healing: "Healing"
        case .resting: "Just used"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .healing: "hourglass"
        case .resting: "pause.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: Theme.ready
        case .healing: Theme.healing
        case .resting: Theme.resting
        }
    }
}

struct SiteReport {
    let status: SiteStatus
    let remaining: TimeInterval
    /// 0 right after use, 1 when fully recovered.
    let progress: Double
}

struct BodySite: Identifiable, Hashable {
    let id: String
    let name: String
    let mode: SiteMapMode
    /// Position relative to the drawing, 0 to 1 on each axis.
    let x: Double
    let y: Double

    static let injection: [BodySite] = [
        BodySite(id: "abd-ur", name: "Abdomen, upper right", mode: .injection, x: 0.38, y: 0.36),
        BodySite(id: "abd-ul", name: "Abdomen, upper left", mode: .injection, x: 0.62, y: 0.36),
        BodySite(id: "abd-lr", name: "Abdomen, lower right", mode: .injection, x: 0.38, y: 0.50),
        BodySite(id: "abd-ll", name: "Abdomen, lower left", mode: .injection, x: 0.62, y: 0.50),
        BodySite(id: "thigh-ru", name: "Right thigh, upper", mode: .injection, x: 0.39, y: 0.72),
        BodySite(id: "thigh-rl", name: "Right thigh, lower", mode: .injection, x: 0.39, y: 0.86),
        BodySite(id: "thigh-lu", name: "Left thigh, upper", mode: .injection, x: 0.61, y: 0.72),
        BodySite(id: "thigh-ll", name: "Left thigh, lower", mode: .injection, x: 0.61, y: 0.86)
    ]

    /// Ten fingertips. Index 0 is the pinky, 4 is the thumb; thumbs point
    /// toward the middle of the drawing.
    static let fingertips: [BodySite] = {
        let names = ["pinky", "ring finger", "middle finger", "index finger", "thumb"]
        let offsets: [Double] = [-0.105, -0.052, 0.0, 0.052, 0.125]
        let heights: [Double] = [0.36, 0.26, 0.22, 0.27, 0.52]
        var result: [BodySite] = []
        for index in names.indices {
            result.append(BodySite(id: "left-\(index)", name: "Left \(names[index])", mode: .fingerPrick, x: 0.27 + offsets[index], y: heights[index]))
            result.append(BodySite(id: "right-\(index)", name: "Right \(names[index])", mode: .fingerPrick, x: 0.73 - offsets[index], y: heights[index]))
        }
        return result
    }()

    static func sites(for mode: SiteMapMode) -> [BodySite] {
        mode == .injection ? injection : fingertips
    }
}

// MARK: - Anxiety

struct GroundingStep: Identifiable {
    let count: Int
    let sense: String
    let symbol: String
    let prompts: [String]

    var id: Int { count }

    var headline: String {
        "\(count) \(count == 1 ? "thing" : "things") you can \(sense)"
    }

    static let all: [GroundingStep] = [
        GroundingStep(count: 5, sense: "see", symbol: "eye.fill", prompts: ["Something blue or green", "Something far away", "Something very close", "Something with a pattern", "Something that is still"]),
        GroundingStep(count: 4, sense: "touch", symbol: "hand.raised.fill", prompts: ["Your feet on the floor", "The fabric you are wearing", "A surface under your hands", "Something cool or warm"]),
        GroundingStep(count: 3, sense: "hear", symbol: "ear.fill", prompts: ["The farthest sound", "The nearest sound", "Your own breath"]),
        GroundingStep(count: 2, sense: "smell", symbol: "nose.fill", prompts: ["Something you like", "Something nearby"]),
        GroundingStep(count: 1, sense: "taste", symbol: "mouth.fill", prompts: ["Something you taste now, or a sip of water"])
    ]
}

// MARK: - App state

/// One observable store for the whole app. Everything lives in memory only:
/// nothing is written to disk and nothing leaves the device.
@MainActor
@Observable
final class AppState {
    // Comfort settings
    var highFocusMode = false
    var soundEnabled = true
    var hapticsEnabled = true
    var demoMode = true

    // Asthma
    var triggerLog: [TriggerEntry] = []

    // Blood pressure
    var postureChecked: Set<PostureStep> = []
    var hasCompletedCalmSession = false
    var calmSessionCount = 0

    // Diabetes
    var plate: [PlacedFood] = []
    var siteLastUsed: [String: Date] = [:]
    var recoveryHours: [SiteMapMode: Double] = [.injection: 168, .fingerPrick: 24]

    // Migraine and anxiety
    var sanctuaryVisits = 0
    var groundingSessions = 0

    init() {
        loadDemoData()
    }

    // MARK: Settings

    func setSound(_ on: Bool) {
        soundEnabled = on
        HapticAudioEngine.shared.soundEnabled = on
        if !on { HapticAudioEngine.shared.stopNoise() }
    }

    func setHaptics(_ on: Bool) {
        hapticsEnabled = on
        HapticAudioEngine.shared.hapticsEnabled = on
        if !on { HapticAudioEngine.shared.stopHaptics() }
    }

    func setDemoMode(_ on: Bool) {
        demoMode = on
        if on { loadDemoData() } else { clearData() }
    }

    // MARK: Demo data

    func loadDemoData() {
        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        triggerLog = [
            TriggerEntry(trigger: .dust, date: ago(27)),
            TriggerEntry(trigger: .coldAir, date: ago(6)),
            TriggerEntry(trigger: .pollen, date: ago(3)),
            TriggerEntry(trigger: .pollen, date: ago(1))
        ]

        postureChecked = [.feet, .back]
        hasCompletedCalmSession = true
        calmSessionCount = 1

        // "Dad's lunch": a little heavy on carbs, so the curve invites a swap.
        let names = ["Brown rice", "Whole-grain bread", "Sweet potato", "Chicken", "Broccoli"]
        plate = names.compactMap { name in FoodItem.catalog.first { $0.name == name } }
            .map { PlacedFood(item: $0) }

        siteLastUsed = [
            "abd-lr": ago(20),
            "abd-ul": ago(72),
            "abd-ur": ago(150),
            "thigh-ru": ago(230),
            "left-3": ago(5),
            "right-2": ago(17),
            "left-1": ago(40)
        ]

        sanctuaryVisits = 2
        groundingSessions = 3
    }

    func clearData() {
        triggerLog = []
        postureChecked = []
        hasCompletedCalmSession = false
        calmSessionCount = 0
        plate = []
        siteLastUsed = [:]
        sanctuaryVisits = 0
        groundingSessions = 0
    }

    // MARK: Asthma

    func logTrigger(_ trigger: AsthmaTrigger) {
        triggerLog.append(TriggerEntry(trigger: trigger, date: Date()))
    }

    func triggerCountToday(_ trigger: AsthmaTrigger) -> Int {
        triggerLog.filter { $0.trigger == trigger && Calendar.current.isDateInToday($0.date) }.count
    }

    var triggersToday: Int {
        triggerLog.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    // MARK: Blood pressure

    func togglePosture(_ step: PostureStep) {
        if postureChecked.contains(step) {
            postureChecked.remove(step)
        } else {
            postureChecked.insert(step)
        }
    }

    func finishCalmSession() {
        hasCompletedCalmSession = true
        calmSessionCount += 1
    }

    // MARK: Diabetes

    var plateAnalysis: PlateAnalysis {
        PlateAnalysis(items: plate.map(\.item))
    }

    func count(in group: FoodGroup) -> Int {
        plate.filter { $0.item.group == group }.count
    }

    /// Returns false when that part of the plate is already full.
    @discardableResult
    func addFood(_ item: FoodItem) -> Bool {
        guard count(in: item.group) < item.group.capacity else { return false }
        plate.append(PlacedFood(item: item))
        return true
    }

    func removeFood(_ id: UUID) {
        plate.removeAll { $0.id == id }
    }

    func clearPlate() {
        plate = []
    }

    func report(for site: BodySite, now: Date) -> SiteReport {
        let window = (recoveryHours[site.mode] ?? 24) * 3600
        guard let last = siteLastUsed[site.id] else {
            return SiteReport(status: .ready, remaining: 0, progress: 1)
        }
        let elapsed = max(0, now.timeIntervalSince(last))
        let progress = min(1, elapsed / window)
        let status: SiteStatus = progress >= 1 ? .ready : (progress < 0.34 ? .resting : .healing)
        return SiteReport(status: status, remaining: max(0, window - elapsed), progress: progress)
    }

    func markUsed(_ site: BodySite) {
        siteLastUsed[site.id] = Date()
    }

    func resetSite(_ site: BodySite) {
        siteLastUsed[site.id] = nil
    }

    func readySiteCount(_ mode: SiteMapMode) -> Int {
        let now = Date()
        return BodySite.sites(for: mode).filter { report(for: $0, now: now).status == .ready }.count
    }

    // MARK: Dashboard summaries (demo mode only)

    func demoStatus(for module: CareModule) -> String? {
        guard demoMode else { return nil }
        switch module {
        case .asthma:
            let count = triggersToday
            return count == 0 ? "No triggers logged today" : "\(count) \(count == 1 ? "trigger" : "triggers") logged today"
        case .bloodPressure:
            return hasCompletedCalmSession
                ? "Calm session done, \(postureChecked.count) of 3 posture checks"
                : "Posture check \(postureChecked.count) of 3"
        case .diabetes:
            let total = BodySite.injection.count
            return "\(plateAnalysis.verdict). \(readySiteCount(.injection)) of \(total) sites ready."
        case .migraine:
            return "Quiet room visits this week: \(sanctuaryVisits)"
        case .anxiety:
            return "\(groundingSessions) grounding journeys this week"
        }
    }
}

// MARK: - Formatting

func shortDuration(_ interval: TimeInterval) -> String {
    let minutes = Int(interval / 60)
    let days = minutes / 1440
    let hours = (minutes % 1440) / 60
    let mins = minutes % 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(mins)m" }
    return "\(max(1, mins))m"
}
