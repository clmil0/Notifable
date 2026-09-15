import SwiftUI
import WidgetKit
import Charts

/// "Ritmo del mes": cuánto llevas, leído contra el presupuesto.
struct PaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.pace, provider: SnapshotProvider()) { entry in
            PaceWidgetView(entry: entry)
                .widgetURL(AppDeepLink.summary.url)
        }
        .configurationDisplayName("Ritmo del mes")
        .description("Lo que llevas gastado y si vas bien contra tu presupuesto.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct PaceWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        if let snapshot = entry.snapshot, let derived = entry.derived {
            switch family {
            case .accessoryCircular:
                PaceCircular(snapshot: snapshot, derived: derived)
                    .containerBackground(for: .widget) { Color.clear }
            case .accessoryRectangular:
                PaceRectangular(snapshot: snapshot, derived: derived, date: entry.date)
                    .containerBackground(for: .widget) { Color.clear }
            case .accessoryInline:
                Text(inlineText(snapshot, derived))
            case _ where !derived.isCurrentMonth:
                PenguinMessage(snapshot: snapshot, title: "Mes nuevo",
                               subtitle: "Abre la app para empezar " + WidgetFormat.monthName(entry.date).lowercased(),
                               horizontal: family == .systemMedium)
                    .widgetBackground()
            case .systemMedium:
                HStack(spacing: 16) {
                    PaceSummary(snapshot: snapshot, derived: derived, date: entry.date)
                    VStack(alignment: .leading, spacing: 6) {
                        MonthCurve(snapshot: snapshot, derived: derived)
                        if let perDay = derived.availablePerDayCents {
                            Text(WidgetFormat.money(perDay, hidden: snapshot.hideAmounts) + "/día disponible")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WidgetPalette.secondary)
                                .lineLimit(1)
                                .privacySensitive()
                        }
                    }
                }
                .widgetBackground()
            default:
                if !showsBackground, derived.usedFraction != nil {
                    PaceStandBy(snapshot: snapshot, derived: derived)
                        .widgetBackground()
                } else {
                    PaceSummary(snapshot: snapshot, derived: derived, date: entry.date)
                        .widgetBackground()
                }
            }
        } else {
            switch family {
            case .accessoryInline:
                Text("AgruPay")
            case .accessoryCircular, .accessoryRectangular:
                WidgetPenguin(nil, monochrome: true)
                    .padding(6)
                    .containerBackground(for: .widget) { Color.clear }
            default:
                EmptySnapshotView(horizontal: family == .systemMedium).widgetBackground()
            }
        }
    }

    private func inlineText(_ snapshot: WidgetSnapshot, _ derived: WidgetDerived) -> String {
        if let used = derived.usedFraction, snapshot.hideAmounts {
            return WidgetFormat.percent(used) + " del presupuesto"
        }
        return WidgetFormat.money(derived.spentCents, hidden: snapshot.hideAmounts) + " este mes"
    }
}

/// Mes, monto, "de S/ 2,000 · quedan S/ 760", barra de ritmo y la frase del ritmo.
struct PaceSummary: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived
    let date: Date

    var body: some View {
        let hidden = snapshot.hideAmounts

        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(WidgetFormat.monthName(date))

            Group {
                if hidden, let used = derived.usedFraction {
                    Text(WidgetFormat.percent(used))
                } else {
                    Text(WidgetFormat.money(derived.spentCents, hidden: hidden))
                }
            }
            .font(.system(size: 28, weight: .bold))
            .tracking(-0.8)
            .foregroundStyle(WidgetPalette.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .privacySensitive()
            .contentTransition(.numericText())
            .padding(.top, 7)

            if let target = derived.targetCents, let remaining = derived.remainingCents {
                Text("de " + WidgetFormat.money(target, hidden: hidden) + " · quedan " + WidgetFormat.money(remaining, hidden: hidden))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
                    .padding(.top, 3)
            }

            Spacer(minLength: 0)

            if let used = derived.usedFraction, let status = derived.status {
                PaceBar(used: used, expected: derived.expectedFraction, tint: status.color)
                Text(derived.paceLine(hidden: hidden) ?? status.headline)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .privacySensitive()
                    .padding(.top, 8)
            } else {
                Text("Hoy " + WidgetFormat.money(derived.todayCents, hidden: hidden))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .privacySensitive()
                if let change = derived.changeVsPrevious {
                    Text(WidgetFormat.change(change) + " vs. " + WidgetFormat.previousMonthName(snapshot).lowercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetPalette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// StandBy: sin fondo, el pingüino dorado dice cómo vas.
struct PaceStandBy: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived

    var body: some View {
        let hidden = snapshot.hideAmounts
        let gold = WidgetPalette.standByGold

        HStack(spacing: 12) {
            WidgetPenguin(snapshot, mood: derived.mood, monochrome: true)
                .foregroundStyle(gold)
                .frame(width: 52, height: 52)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 6) {
                Text((derived.status ?? .ok).headline.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Group {
                    if let perDay = derived.availablePerDayCents {
                        Text(WidgetFormat.money(perDay, hidden: hidden))
                            + Text(" /día").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    } else {
                        Text(WidgetFormat.money(derived.remainingCents ?? 0, hidden: hidden))
                    }
                }
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .privacySensitive()
                PaceBar(used: derived.usedFraction ?? 0, expected: derived.expectedFraction, tint: gold,
                        track: .white.opacity(0.18), marker: .white, height: 8)
                if let target = derived.targetCents {
                    Text(WidgetFormat.money(derived.spentCents, hidden: hidden) + " de " + WidgetFormat.money(target, hidden: hidden))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Gasto acumulado del mes con la línea del presupuesto, en su recuadro.
struct MonthCurve: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived

    var body: some View {
        let accent = WidgetPalette.amber
        let points = Array(derived.cumulativeCents.enumerated())
        let top = max(derived.targetCents ?? 0, derived.cumulativeCents.last ?? 0, 1)

        Chart {
            ForEach(points, id: \.offset) { point in
                AreaMark(x: .value("Día", point.offset + 1),
                         y: .value("Gasto", point.element))
                    .foregroundStyle(accent.opacity(0.22))
                LineMark(x: .value("Día", point.offset + 1),
                         y: .value("Gasto", point.element))
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            if let last = points.last {
                PointMark(x: .value("Día", last.offset + 1), y: .value("Gasto", last.element))
                    .foregroundStyle(accent)
                    .symbolSize(40)
            }
            if let target = derived.targetCents {
                // Lo esperado a cada día: de cero al presupuesto el último día.
                LineMark(x: .value("Día", 1), y: .value("Esperado", target / derived.totalDays), series: .value("Serie", "meta"))
                    .foregroundStyle(WidgetPalette.ink.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                LineMark(x: .value("Día", derived.totalDays), y: .value("Esperado", target), series: .value("Serie", "meta"))
                    .foregroundStyle(WidgetPalette.ink.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartXScale(domain: 1...max(2, derived.totalDays))
        .chartYScale(domain: 0...top)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.padding(.vertical, 4) }
        .widgetAccentable()
        .background(WidgetPalette.curve, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Pantalla bloqueada: el anillo del presupuesto con tu pingüino en silueta.
struct PaceCircular: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived

    var body: some View {
        if let used = derived.usedFraction {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(used, 1))
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                WidgetPenguin(snapshot, mood: derived.mood, monochrome: true)
                    .foregroundStyle(.white)
                    .padding(11)
            }
            .padding(2)
            .accessibilityLabel(WidgetFormat.percent(used) + " del presupuesto")
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(WidgetFormat.monthName(snapshot.month.start, abbreviated: true))
                        .font(.system(size: 9, weight: .semibold))
                    Text(WidgetFormat.compactMoney(derived.spentCents, hidden: snapshot.hideAmounts)
                        .replacingOccurrences(of: "S/ ", with: ""))
                        .font(.system(size: 13, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .privacySensitive()
                }
                .padding(4)
            }
        }
    }
}

/// "Setiembre / S/ 1,240 · 62 % / barra / S/ 51 por día".
struct PaceRectangular: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived
    let date: Date

    var body: some View {
        let hidden = snapshot.hideAmounts

        VStack(alignment: .leading, spacing: 3) {
            Text(WidgetFormat.monthName(date))
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.85)
                .widgetAccentable()
            if let used = derived.usedFraction {
                Text(hidden
                     ? WidgetFormat.percent(used) + " usado"
                     : WidgetFormat.money(derived.spentCents, hidden: false) + " · " + WidgetFormat.percent(used))
                    .font(.system(size: 14, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .privacySensitive()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white)
                            .frame(width: max(6, geo.size.width * min(used, 1)))
                            .widgetAccentable()
                    }
                }
                .frame(height: 6)
                if let perDay = derived.availablePerDayCents {
                    Text(WidgetFormat.money(perDay, hidden: hidden) + " por día")
                        .font(.system(size: 10, weight: .medium))
                        .opacity(0.6)
                        .lineLimit(1)
                        .privacySensitive()
                }
            } else {
                Text(WidgetFormat.money(derived.spentCents, hidden: hidden))
                    .font(.system(size: 14, weight: .semibold))
                    .privacySensitive()
                Text("Hoy " + WidgetFormat.money(derived.todayCents, hidden: hidden))
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.6)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
