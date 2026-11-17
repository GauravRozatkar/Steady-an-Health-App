import SwiftUI
import UIKit

// MARK: - Dynamic colors
// Every color is a light/dark pair, so contrast stays strong in both
// appearances without any per-view branching.

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Three tones per module: `deep` for text and strong shapes, `mid` for
/// illustrations, `soft` for card washes.
struct ModulePalette {
    let deep: Color
    let mid: Color
    let soft: Color
}

enum Theme {
    static let canvas = Color(light: 0xFBF6EE, dark: 0x16130F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x221E19)
    static let ink = Color(light: 0x2B2622, dark: 0xF3EBDD)
    static let inkSoft = Color(light: 0x5A5048, dark: 0xCBBFAE)
    /// Text or icons placed on top of a `deep` fill.
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x16130F)
    static let accent = Color(light: 0x3F6249, dark: 0xA9CDB0)

    // Status colors always travel with a symbol and a word, never color alone.
    static let ready = Color(light: 0x3F7A4D, dark: 0x8CC79A)
    static let healing = Color(light: 0xA9740F, dark: 0xF0C060)
    static let resting = Color(light: 0xB24A2E, dark: 0xF09A80)

    // Migraine sanctuary: warm amber on charcoal, no blue light.
    static let charcoal = Color(hex: 0x100D0A)
    static let ember = Color(hex: 0xE9A04B)
}

extension CareModule {
    var palette: ModulePalette {
        switch self {
        case .asthma: // soft sage
            return ModulePalette(
                deep: Color(light: 0x3F6249, dark: 0xA9CDB0),
                mid: Color(light: 0x7FA487, dark: 0x6F9678),
                soft: Color(light: 0xE3EEDF, dark: 0x24322A))
        case .bloodPressure: // warm terracotta
            return ModulePalette(
                deep: Color(light: 0x9C4A30, dark: 0xF0A98F),
                mid: Color(light: 0xD2765A, dark: 0xC0684D),
                soft: Color(light: 0xF8E3DA, dark: 0x38241D))
        case .diabetes: // calm slate blue
            return ModulePalette(
                deep: Color(light: 0x3A5877, dark: 0xA6C3E3),
                mid: Color(light: 0x6F8FB3, dark: 0x5E7E9F),
                soft: Color(light: 0xDEE7F2, dark: 0x1F2B38))
        case .migraine: // muted amber
            return ModulePalette(
                deep: Color(light: 0x86590A, dark: 0xF2C46A),
                mid: Color(light: 0xD9A23A, dark: 0xB88A2E),
                soft: Color(light: 0xFAEDCB, dark: 0x36290F))
        case .anxiety: // deep lavender
            return ModulePalette(
                deep: Color(light: 0x5A4685, dark: 0xCBBBEB),
                mid: Color(light: 0x8E79BD, dark: 0x7B67A8),
                soft: Color(light: 0xEAE3F5, dark: 0x2D2540))
        }
    }
}

// MARK: - High-Focus Calm Mode
// One environment flag. Components read it to enlarge touch targets, add
// spacing and drop decoration. Views never branch on device type.

private struct HighFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var highFocus: Bool {
        get { self[HighFocusKey.self] }
        set { self[HighFocusKey.self] = newValue }
    }
}

// MARK: - Buttons

struct CalmButtonStyle: ButtonStyle {
    var tint: Color
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        CalmButtonBody(configuration: configuration, tint: tint, prominent: prominent)
    }
}

// The body lives in a View so it can read the environment and use
// @ScaledMetric, which keeps the minimum height growing with Dynamic Type.
private struct CalmButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let prominent: Bool
    @Environment(\.highFocus) private var highFocus
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var baseHeight: CGFloat = 52

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        configuration.label
            .font(.system(.headline, design: .rounded))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: highFocus ? baseHeight * 1.5 : baseHeight)
            .padding(.horizontal, 16)
            .foregroundStyle(prominent ? Theme.onAccent : tint)
            .background(shape.fill(prominent ? tint : tint.opacity(0.14)))
            .overlay(shape.strokeBorder(tint.opacity(prominent ? 0 : 0.55), lineWidth: 1.5))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Layout helpers

extension View {
    /// Keeps reading width comfortable on iPad and Mac while staying fluid on iPhone.
    func readableColumn(maxWidth: CGFloat = 760) -> some View {
        frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    }

    func calmBackground(_ palette: ModulePalette?) -> some View {
        background {
            LinearGradient(
                colors: [palette?.soft ?? Theme.canvas, Theme.canvas],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    /// Reports the rendered size so Canvas taps can be converted into
    /// relative positions. Uses the iOS 18 API rather than GeometryReader.
    func trackSize(_ size: Binding<CGSize>) -> some View {
        onGeometryChange(for: CGSize.self, of: { $0.size }, action: { size.wrappedValue = $0 })
    }
}

/// Standard scrolling page for a module: palette wash, readable column,
/// inline title. High-Focus mode increases the vertical rhythm.
struct ModuleScaffold<Content: View>: View {
    let module: CareModule
    @ViewBuilder var content: Content
    @Environment(\.highFocus) private var highFocus

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: highFocus ? 28 : 20) {
                ModuleHeader(module: module)
                content
            }
            .padding()
            .readableColumn()
        }
        .scrollBounceBehavior(.basedOnSize)
        .calmBackground(module.palette)
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(module.palette.deep)
    }
}

struct ModuleHeader: View {
    let module: CareModule
    @Environment(\.highFocus) private var highFocus

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: module.symbol)
                .font(.title)
                .foregroundStyle(Theme.onAccent)
                .padding(14)
                .background(Circle().fill(module.palette.deep))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(module.subtitle)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(module.palette.deep)
                if !highFocus {
                    Text(module.tagline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A rounded section card with an optional title row.
struct CalmPanel<Content: View>: View {
    var palette: ModulePalette
    var title: String? = nil
    var symbol: String? = nil
    var filled = true
    @ViewBuilder var content: Content
    @Environment(\.highFocus) private var highFocus

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(alignment: .leading, spacing: highFocus ? 18 : 14) {
            if let title {
                Label {
                    Text(title).font(.system(.title3, design: .rounded, weight: .bold))
                } icon: {
                    if let symbol { Image(systemName: symbol) }
                }
                .foregroundStyle(palette.deep)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(highFocus ? 22 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(filled ? palette.soft : Theme.surface))
        .overlay(shape.strokeBorder(palette.deep.opacity(0.12), lineWidth: 1))
    }
}

/// Plain-language reminder that this is comfort support, not medical care.
struct SafetyNote: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Drawing helpers
// Canvas drawings use relative geometry only, so they scale with any container.

enum Draw {
    /// Point on a circle. Angles are degrees, 0 = right, 90 = down (y grows downward).
    static func point(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }

    /// Pie slice built from short line segments. Sampling avoids the
    /// clockwise ambiguity of Path.addArc in a flipped coordinate space.
    static func sector(center: CGPoint, radius: CGFloat, from start: Double, to end: Double) -> Path {
        var path = Path()
        path.move(to: center)
        var angle = start
        path.addLine(to: point(center, radius, angle))
        while angle < end {
            angle = min(angle + 2, end)
            path.addLine(to: point(center, radius, angle))
        }
        path.closeSubpath()
        return path
    }

    static func arc(center: CGPoint, radius: CGFloat, from start: Double, to end: Double) -> Path {
        var path = Path()
        path.move(to: point(center, radius, start))
        var angle = start
        while angle < end {
            angle = min(angle + 2, end)
            path.addLine(to: point(center, radius, angle))
        }
        return path
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Fractional part, used for stable pseudo-random placement.
    static func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}
