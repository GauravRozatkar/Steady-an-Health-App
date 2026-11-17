import SwiftUI

// Diabetes: tap-to-place plate (half veggies, a quarter protein, a quarter
// complex carbs) with a live, illustrative "steady glucose" curve, and a
// rotation map that shows which injection or fingertip sites are ready again.
// Both interactive drawings also have plain list equivalents for VoiceOver.

struct DiabetesView: View {
    @Environment(AppState.self) private var state
    @State private var notice: String?
    @State private var mode: SiteMapMode = .injection
    @State private var selectedSiteID: String?
    @ScaledMetric(relativeTo: .body) private var tokenMinimum: CGFloat = 84
    @ScaledMetric(relativeTo: .body) private var siteMinimum: CGFloat = 170
    @ScaledMetric(relativeTo: .body) private var chipMinimum: CGFloat = 130

    private let palette = CareModule.diabetes.palette
    private let engine = HapticAudioEngine.shared

    var body: some View {
        ModuleScaffold(module: .diabetes) {
            platePanel
            trayPanel
            sitePanel
            SafetyNote(text: "The curve is an illustration of how balance can smooth a meal. It is not a glucose reading or dosing advice. Follow your care team's plan, and recovery windows are examples you can adjust.")
        }
    }

    // MARK: Plate and curve

    private var platePanel: some View {
        let analysis = state.plateAnalysis
        return CalmPanel(palette: palette, title: "Build your plate", symbol: "fork.knife") {
            PlateCanvas(placed: state.plate, palette: palette) { food in
                state.removeFood(food.id)
                engine.cue(.soft)
            }
            .readableColumn(maxWidth: 460)

            if let notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(palette.deep)
                    .transition(.opacity)
            }

            if !state.plate.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: chipMinimum), spacing: 8)], spacing: 8) {
                    ForEach(state.plate) { food in
                        Button {
                            state.removeFood(food.id)
                            engine.cue(.soft)
                        } label: {
                            Label(food.item.name, systemImage: "xmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(Theme.ink)
                                .background(Capsule().fill(Theme.surface))
                                .overlay(Capsule().strokeBorder(food.item.group.tint.opacity(0.6), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(food.item.name)")
                    }
                }
                Button("Clear plate") {
                    state.clearPlate()
                    engine.cue(.tap)
                }
                .buttonStyle(CalmButtonStyle(tint: palette.deep, prominent: false))
            }

            Divider()
            curveBlock(analysis)
        }
    }

    private func curveBlock(_ analysis: PlateAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(analysis.verdict, systemImage: analysis.verdictSymbol)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(palette.deep)

            ZStack {
                ComfortBand().fill(Theme.ready.opacity(0.14))
                GlucoseCurve(load: analysis.load, fiber: analysis.fiber, protein: analysis.protein, closed: true)
                    .fill(LinearGradient(colors: [palette.mid.opacity(0.45), palette.mid.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                GlucoseCurve(load: analysis.load, fiber: analysis.fiber, protein: analysis.protein, closed: false)
                    .stroke(palette.deep, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            .aspectRatio(2, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .animation(.smooth(duration: 0.6), value: state.plate.count)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Illustrative steady glucose curve over three hours. \(analysis.verdict).")

            HStack {
                Text("Now")
                Spacer()
                Text("1 hr")
                Spacer()
                Text("2 hr")
                Spacer()
                Text("3 hr")
            }
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
            .accessibilityHidden(true)

            Label("Green band: a calm zone", systemImage: "square.fill")
                .font(.caption)
                .foregroundStyle(Theme.ready)

            Gauge(value: analysis.balance) {
                Text("Plate balance")
            } currentValueLabel: {
                Text("\(Int(analysis.balance * 100))%")
            }
            .gaugeStyle(.linearCapacity)
            .tint(palette.deep)

            Text(analysis.nudge)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
    }

    // MARK: Food tray

    private var trayPanel: some View {
        CalmPanel(palette: palette, title: "Tap a food to place it", symbol: "hand.tap.fill") {
            ForEach(FoodGroup.allCases) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(group.title, systemImage: group.symbol)
                            .font(.headline)
                            .foregroundStyle(group.tint)
                        Spacer()
                        Text("\(group.shareText) · \(state.count(in: group)) of \(group.capacity)")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: tokenMinimum), spacing: 12)], spacing: 12) {
                        ForEach(FoodItem.catalog.filter { $0.group == group }) { item in
                            FoodToken(item: item) { add(item) }
                        }
                    }
                }
            }
        }
    }

    private func add(_ item: FoodItem) {
        if state.addFood(item) {
            engine.cue(.soft)
            engine.chime(.step(state.plate.count))
            withAnimation(.smooth) { notice = nil }
        } else {
            engine.cue(.selection)
            let message = "That part of the plate is full. Remove one, or try another group."
            withAnimation(.smooth) { notice = message }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    // MARK: Site rotation

    private var sitePanel: some View {
        CalmPanel(palette: palette, title: "Site rotation map", symbol: "arrow.triangle.2.circlepath") {
            Picker("Site type", selection: $mode) {
                ForEach(SiteMapMode.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                selectedSiteID = nil
                engine.cue(.selection)
            }

            // Timers refresh every 30 seconds without any manual timer code.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                siteContent(now: context.date)
            }
        }
    }

    @ViewBuilder
    private func siteContent(now: Date) -> some View {
        let sites = BodySite.sites(for: mode)
        let reports = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, state.report(for: $0, now: now)) })
        VStack(spacing: 14) {
            SiteMapCanvas(mode: mode, sites: sites, reports: reports, selectedID: selectedSiteID, palette: palette) { site in
                select(site)
            }
            legend

            if let site = sites.first(where: { $0.id == selectedSiteID }), let report = reports[site.id] {
                detailCard(site: site, report: report)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: siteMinimum), spacing: 10)], spacing: 10) {
                ForEach(sites) { site in
                    if let report = reports[site.id] {
                        SiteChip(site: site, report: report, isSelected: site.id == selectedSiteID) {
                            select(site)
                        }
                    }
                }
            }
            recoveryStepper
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach([SiteStatus.ready, .healing, .resting], id: \.title) { status in
                Label(status.title, systemImage: status.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(status.color)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: ready, healing, just used")
    }

    private func detailCard(site: BodySite, report: SiteReport) -> some View {
        let line: String
        switch report.status {
        case .ready: line = "Ready to use"
        case .healing: line = "Healing, ready in \(shortDuration(report.remaining))"
        case .resting: line = "Just used, ready in \(shortDuration(report.remaining))"
        }
        let used = state.siteLastUsed[site.id] != nil
        return VStack(alignment: .leading, spacing: 10) {
            Label(site.name, systemImage: report.status.symbol)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(report.status.color)
            Text(line)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Button("Mark used now") {
                    state.markUsed(site)
                    engine.cue(.tap)
                    engine.chime(.step(3))
                    AccessibilityNotification.Announcement("\(site.name) marked as used").post()
                }
                .buttonStyle(CalmButtonStyle(tint: palette.deep))
                if used {
                    Button("Set to ready") {
                        state.resetSite(site)
                        engine.cue(.soft)
                    }
                    .buttonStyle(CalmButtonStyle(tint: palette.deep, prominent: false))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
    }

    private var recoveryStepper: some View {
        let hours = state.recoveryHours[mode] ?? 24
        let step: Double = mode == .injection ? 24 : 12
        let range: ClosedRange<Double> = mode == .injection ? 24...336 : 12...72
        let text = hours >= 48 ? "\(Int(hours / 24)) days" : "\(Int(hours)) hours"
        return VStack(alignment: .leading, spacing: 4) {
            Stepper(value: Binding(
                get: { state.recoveryHours[mode] ?? hours },
                set: { state.recoveryHours[mode] = $0 }
            ), in: range, step: step) {
                Text("Recovery window: \(text)")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            Text("An example you can change. Ask your care team what suits you.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func select(_ site: BodySite) {
        selectedSiteID = site.id
        engine.cue(.selection)
    }
}

// MARK: - Food token

private struct FoodToken: View {
    let item: FoodItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(item.tint)
                    Image(systemName: item.symbol)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .aspectRatio(1, contentMode: .fit)
                Text(item.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(item.name)")
        .accessibilityHint(item.group.title)
    }
}

// MARK: - Plate drawing

private enum PlateLayout {
    /// Angles in degrees, 0 = right, 90 = down. Veggies take the left half.
    static func range(_ group: FoodGroup) -> (start: Double, end: Double) {
        switch group {
        case .veggies: (90, 270)
        case .protein: (270, 360)
        case .carbs: (0, 90)
        }
    }

    static func plateRadius(_ size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.47
    }

    static func slot(_ group: FoodGroup, index: Int, size: CGSize) -> (center: CGPoint, radius: CGFloat) {
        let radius = plateRadius(size)
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        let bounds = range(group)
        let mid = (bounds.start + bounds.end) / 2
        let span = bounds.end - bounds.start
        let perRing = group == .veggies ? 4 : 2
        let ring = index / perRing
        let position = index % perRing
        let spread = span * (group == .veggies ? 0.70 : 0.60)
        let angle = mid - spread / 2 + spread * Double(position) / Double(max(1, perRing - 1))
        let distance = radius * (ring == 0 ? 0.42 : 0.74)
        return (Draw.point(middle, distance, angle), radius * 0.125)
    }

    static func assignments(_ placed: [PlacedFood], size: CGSize) -> [(food: PlacedFood, center: CGPoint, radius: CGFloat)] {
        var result: [(food: PlacedFood, center: CGPoint, radius: CGFloat)] = []
        for group in FoodGroup.allCases {
            let foods = placed.filter { $0.item.group == group }
            for (index, food) in foods.enumerated() where index < group.capacity {
                let placement = slot(group, index: index, size: size)
                result.append((food, placement.center, placement.radius))
            }
        }
        return result
    }
}

private struct PlateCanvas: View {
    let placed: [PlacedFood]
    let palette: ModulePalette
    let onRemove: (PlacedFood) -> Void
    @State private var size: CGSize = .zero

    var body: some View {
        Canvas { context, canvasSize in
            Self.draw(&context, canvasSize, placed, palette)
        }
        .aspectRatio(1, contentMode: .fit)
        .trackSize($size)
        .gesture(SpatialTapGesture().onEnded { value in remove(at: value.location) })
        .accessibilityHidden(true) // the chips below are the accessible equivalent
    }

    private func remove(at location: CGPoint) {
        let hits = PlateLayout.assignments(placed, size: size)
        if let hit = hits.first(where: { hypot($0.center.x - location.x, $0.center.y - location.y) <= max($0.radius * 1.3, 22) }) {
            onRemove(hit.food)
        }
    }

    private static func draw(_ context: inout GraphicsContext, _ size: CGSize, _ placed: [PlacedFood], _ palette: ModulePalette) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = PlateLayout.plateRadius(size)

        context.fill(Draw.circle(center, radius * 1.05), with: .color(palette.deep.opacity(0.12)))
        context.fill(Draw.circle(center, radius), with: .color(Theme.surface))

        for group in FoodGroup.allCases {
            let bounds = PlateLayout.range(group)
            let sector = Draw.sector(center: center, radius: radius * 0.96, from: bounds.start, to: bounds.end)
            context.fill(sector, with: .color(group.tint.opacity(0.16)))
            context.stroke(sector, with: .color(group.tint.opacity(0.5)), style: StrokeStyle(lineWidth: max(1.5, radius * 0.01), lineJoin: .round))
        }

        // Dashed guides show where the next food will land.
        for group in FoodGroup.allCases {
            for index in 0..<group.capacity {
                let slot = PlateLayout.slot(group, index: index, size: size)
                context.stroke(
                    Draw.circle(slot.center, slot.radius),
                    with: .color(group.tint.opacity(0.35)),
                    style: StrokeStyle(lineWidth: max(1, radius * 0.008), dash: [4, 4])
                )
            }
        }

        for entry in PlateLayout.assignments(placed, size: size) {
            let item = entry.food.item
            let shadow = CGPoint(x: entry.center.x, y: entry.center.y + entry.radius * 0.12)
            context.fill(Draw.circle(shadow, entry.radius), with: .color(.black.opacity(0.15)))
            context.fill(Draw.circle(entry.center, entry.radius), with: .color(item.tint))
            context.stroke(Draw.circle(entry.center, entry.radius), with: .color(.white.opacity(0.85)), lineWidth: max(1.5, entry.radius * 0.1))

            var image = context.resolve(Image(systemName: item.symbol))
            image.shading = .color(.white)
            let natural = image.size
            let scale = (entry.radius * 1.15) / max(natural.width, natural.height, 1)
            let drawSize = CGSize(width: natural.width * scale, height: natural.height * scale)
            context.draw(image, in: CGRect(
                x: entry.center.x - drawSize.width / 2,
                y: entry.center.y - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
    }
}

// MARK: - Glucose curve shapes

/// Animatable, so the curve morphs smoothly as foods are added or removed.
private struct GlucoseCurve: Shape {
    var load: Double
    var fiber: Double
    var protein: Double
    var closed: Bool

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(load, AnimatablePair(fiber, protein)) }
        set {
            load = newValue.first
            fiber = newValue.second.first
            protein = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 60
        for index in 0...steps {
            let minute = 180.0 * Double(index) / Double(steps)
            let value = GlucoseModel.value(atMinute: minute, load: load, fiber: fiber, protein: protein)
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(steps)
            let y = rect.maxY - rect.height * CGFloat(min(value, GlucoseModel.ceiling) / GlucoseModel.ceiling)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

private struct ComfortBand: Shape {
    func path(in rect: CGRect) -> Path {
        let top = rect.maxY - rect.height * CGFloat(GlucoseModel.bandHigh / GlucoseModel.ceiling)
        let bottom = rect.maxY - rect.height * CGFloat(GlucoseModel.bandLow / GlucoseModel.ceiling)
        return Path(CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top))
    }
}

// MARK: - Site map

private struct SiteChip: View {
    let site: BodySite
    let report: SiteReport
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.highFocus) private var highFocus
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 56

    private var statusText: String {
        report.status == .ready ? "Ready" : "\(report.status.title), \(shortDuration(report.remaining)) left"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: report.status.symbol)
                    .foregroundStyle(report.status.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: highFocus ? minHeight * 1.3 : minHeight, alignment: .leading)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(isSelected ? Theme.ink : report.status.color.opacity(0.45), lineWidth: isSelected ? 2.5 : 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(site.name), \(statusText)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct SiteMapCanvas: View {
    let mode: SiteMapMode
    let sites: [BodySite]
    let reports: [String: SiteReport]
    let selectedID: String?
    let palette: ModulePalette
    let onSelect: (BodySite) -> Void
    @State private var size: CGSize = .zero

    var body: some View {
        Canvas { context, canvasSize in
            if mode == .injection {
                Self.drawTorso(&context, canvasSize, palette)
            } else {
                Self.drawHands(&context, canvasSize, palette)
            }
            let radius = canvasSize.width * (mode == .injection ? 0.05 : 0.038)
            for site in sites {
                Self.drawSite(&context, canvasSize, radius, site, reports[site.id], site.id == selectedID)
            }
        }
        .aspectRatio(mode == .injection ? 0.8 : 1.5, contentMode: .fit)
        .trackSize($size)
        .gesture(SpatialTapGesture().onEnded { value in pick(value.location) })
        .accessibilityHidden(true) // the chips below are the accessible equivalent
        .readableColumn(maxWidth: mode == .injection ? 380 : 560)
    }

    private func pick(_ location: CGPoint) {
        guard size.width > 0 else { return }
        var best: (site: BodySite, distance: CGFloat)?
        for site in sites {
            let dx = CGFloat(site.x) * size.width - location.x
            let dy = CGFloat(site.y) * size.height - location.y
            let distance = hypot(dx, dy)
            if best == nil || distance < best!.distance {
                best = (site, distance)
            }
        }
        // Generous tolerance keeps small targets easy to hit with a finger.
        let limit = max(size.width * 0.11, 44)
        if let best, best.distance <= limit {
            onSelect(best.site)
        }
    }

    private static func drawTorso(_ context: inout GraphicsContext, _ s: CGSize, _ palette: ModulePalette) {
        let w = s.width
        let h = s.height
        func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ corner: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x0 * w, y: y0 * h, width: (x1 - x0) * w, height: (y1 - y0) * h), cornerRadius: corner * w)
        }
        let shapes: [Path] = [
            box(0.29, 0.64, 0.49, 0.97, 0.07),
            box(0.51, 0.64, 0.71, 0.97, 0.07),
            box(0.29, 0.54, 0.71, 0.66, 0.06),
            box(0.14, 0.16, 0.25, 0.56, 0.05),
            box(0.75, 0.16, 0.86, 0.56, 0.05),
            box(0.27, 0.13, 0.73, 0.60, 0.14),
            Path(ellipseIn: CGRect(x: 0.435 * w, y: 0.012 * h, width: 0.13 * w, height: 0.13 * w))
        ]
        for shape in shapes {
            context.fill(shape, with: .color(Theme.surface))
            context.fill(shape, with: .color(palette.deep.opacity(0.10)))
            context.stroke(shape, with: .color(palette.deep.opacity(0.35)), lineWidth: 1.5)
        }
        context.fill(Draw.circle(CGPoint(x: 0.5 * w, y: 0.45 * h), w * 0.008), with: .color(palette.deep.opacity(0.4)))
    }

    private static func drawHands(_ context: inout GraphicsContext, _ s: CGSize, _ palette: ModulePalette) {
        let w = s.width
        let h = s.height
        let fingerWidth = w * 0.05
        let outline = palette.deep.opacity(0.35)
        let wash = palette.deep.opacity(0.10)

        for (centerX, thumbSign) in [(0.27, 1.0), (0.73, -1.0)] {
            let isLeft = centerX < 0.5

            // Fingers first, so the palm overlaps their bases.
            for site in BodySite.fingertips where site.id.hasPrefix(isLeft ? "left-" : "right-") {
                let isThumb = site.id.hasSuffix("-4")
                let tip = CGPoint(x: site.x * w, y: site.y * h)
                let base = isThumb
                    ? CGPoint(x: (centerX + thumbSign * 0.075) * w, y: 0.70 * h)
                    : CGPoint(x: (centerX + (site.x - centerX) * 0.6) * w, y: 0.54 * h)
                var finger = Path()
                finger.move(to: base)
                finger.addLine(to: tip)
                context.stroke(finger, with: .color(outline), style: StrokeStyle(lineWidth: fingerWidth + 3, lineCap: .round))
                context.stroke(finger, with: .color(Theme.surface), style: StrokeStyle(lineWidth: fingerWidth, lineCap: .round))
                context.stroke(finger, with: .color(wash), style: StrokeStyle(lineWidth: fingerWidth, lineCap: .round))
            }

            let palm = Path(roundedRect: CGRect(x: (centerX - 0.085) * w, y: 0.5 * h, width: 0.17 * w, height: 0.4 * h), cornerRadius: w * 0.05)
            context.fill(palm, with: .color(Theme.surface))
            context.fill(palm, with: .color(wash))
            context.stroke(palm, with: .color(outline), lineWidth: 1.5)
        }
    }

    private static func drawSite(
        _ context: inout GraphicsContext,
        _ s: CGSize,
        _ r: CGFloat,
        _ site: BodySite,
        _ report: SiteReport?,
        _ selected: Bool
    ) {
        let p = CGPoint(x: site.x * s.width, y: site.y * s.height)
        let status = report?.status ?? .ready
        let color = status.color
        let progress = report?.progress ?? 1

        if selected {
            context.stroke(Draw.circle(p, r * 1.5), with: .color(Theme.ink), lineWidth: r * 0.22)
        }
        context.fill(Draw.circle(p, r), with: .color(Theme.surface))
        context.fill(Draw.circle(p, r), with: .color(color.opacity(0.22)))
        context.stroke(Draw.circle(p, r), with: .color(color.opacity(0.35)), lineWidth: r * 0.2)
        // The bold arc fills as the site recovers, a timer you can read at a glance.
        context.stroke(
            Draw.arc(center: p, radius: r, from: -90, to: -90 + 360 * progress),
            with: .color(color),
            style: StrokeStyle(lineWidth: r * 0.3, lineCap: .round)
        )

        // Each status also has its own glyph, so color is never the only cue.
        switch status {
        case .ready:
            var tick = Path()
            tick.move(to: CGPoint(x: p.x - r * 0.38, y: p.y + r * 0.02))
            tick.addLine(to: CGPoint(x: p.x - r * 0.08, y: p.y + r * 0.32))
            tick.addLine(to: CGPoint(x: p.x + r * 0.4, y: p.y - r * 0.3))
            context.stroke(tick, with: .color(color), style: StrokeStyle(lineWidth: r * 0.24, lineCap: .round, lineJoin: .round))
        case .healing:
            context.fill(Draw.circle(p, r * 0.2), with: .color(color))
        case .resting:
            for offset in [-0.22, 0.22] {
                let bar = Path(
                    roundedRect: CGRect(x: p.x + CGFloat(offset) * r - r * 0.08, y: p.y - r * 0.3, width: r * 0.16, height: r * 0.6),
                    cornerRadius: r * 0.05
                )
                context.fill(bar, with: .color(color))
            }
        }
    }
}
