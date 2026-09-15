import SwiftUI
import WidgetKit
import Charts

/// "Ritmo del mes": cuánto llevas, leído contra el presupuesto.
struct PaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.pace, provider: SnapshotProvider()) { entry in
            PaceWidgetView(entry: entry)
                .widgetURL(AppDeepLink.summary.url)
                .widgetBackground()
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

    var body: some View {
        if let snapshot = entry.snapshot, let derived = entry.derived {
            switch family {
            case .systemMedium:
                HStack(spacing: 14) {
                    PaceSummary(snapshot: snapshot, derived: derived, date: entry.date)
                    MonthCurve(snapshot: snapshot, derived: derived)
                }
            case .accessoryCircular:
                PaceCircular(snapshot: snapshot, derived: derived)
            case .accessoryRectangular:
                PaceRectangular(snapshot: snapshot, derived: derived, date: entry.date)
            case .accessoryInline:
                Text(inlineText(snapshot, derived))
            default:
                PaceSummary(snapshot: snapshot, derived: derived, date: entry.date)
            }
        } else {
            switch family {
            case .accessoryInline: Text("AgruPay")
            case .accessoryCircular, .accessoryRectangular:
                Image(systemName: "chart.bar.doc.horizontal")
            default: EmptySnapshotView()
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

/// Bloque principal: mes, monto, barra de ritmo y comparación.
struct PaceSummary: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived
    let date: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = snapshot.theme.accent(scheme)
        let hidden = snapshot.hideAmounts

        VStack(alignment: .leading, spacing: 6) {
            Text(WidgetFormat.monthName(date).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if hidden, let used = derived.usedFraction {
                Text(WidgetFormat.percent(used))
                    .font(.title.weight(.bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            } else {
                Text(WidgetFormat.money(derived.spentCents, hidden: hidden))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .privacySensitive()
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            if let used = derived.usedFraction, let status = derived.status {
                PaceBar(used: used, expected: derived.expectedFraction,
                        tint: status == .ok ? accent : status.color)
                HStack(spacing: 4) {
                    Circle().fill(status.color).frame(width: 6, height: 6)
                    Text(hidden ? status.label : WidgetFormat.percent(used) + " usado")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
            } else {
                Text("Hoy " + WidgetFormat.money(derived.todayCents, hidden: hidden))
                    .font(.caption.weight(.medium))
                    .privacySensitive()
            }

            if let change = derived.changeVsPrevious {
                Text(WidgetFormat.change(change) + " vs. " + WidgetFormat.previousMonthName(snapshot).lowercased())
                    .font(.caption2)
                    .foregroundStyle(change > 0 ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else if !derived.isCurrentMonth {
                Text("Mes nuevo · abre la app")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Gasto acumulado del mes con la línea del presupuesto.
struct MonthCurve: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let accent = snapshot.theme.accent(scheme)
        let points = Array(derived.cumulativeCents.enumerated())
        let top = max(derived.targetCents ?? 0, derived.cumulativeCents.last ?? 0, 1)

        VStack(alignment: .leading, spacing: 4) {
            Chart {
                ForEach(points, id: \.offset) { point in
                    AreaMark(x: .value("Día", point.offset + 1),
                             y: .value("Gasto", point.element))
                        .foregroundStyle(accent.opacity(0.18).gradient)
                    LineMark(x: .value("Día", point.offset + 1),
                             y: .value("Gasto", point.element))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if let target = derived.targetCents {
                    // Lo esperado a cada día: de cero al presupuesto el último día.
                    LineMark(x: .value("Día", 1), y: .value("Esperado", target / derived.totalDays), series: .value("Serie", "meta"))
                        .foregroundStyle(.secondary)
                    LineMark(x: .value("Día", derived.totalDays), y: .value("Esperado", target), series: .value("Serie", "meta"))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXScale(domain: 1...max(2, derived.totalDays))
            .chartYScale(domain: 0...top)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .widgetAccentable()

            HStack {
                if let perDay = derived.availablePerDayCents {
                    Text(WidgetFormat.money(perDay, hidden: snapshot.hideAmounts) + "/día disponible")
                        .privacySensitive()
                } else if derived.targetCents == nil {
                    Text("Sin presupuesto")
                } else {
                    Text("Último día del mes")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

struct PaceCircular: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived

    var body: some View {
        if let used = derived.usedFraction {
            Gauge(value: min(used, 1)) {
                Image(systemName: "creditcard")
            } currentValueLabel: {
                Text("\(Int((used * 100).rounded()))")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
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

struct PaceRectangular: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WidgetFormat.monthName(date))
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            if let used = derived.usedFraction {
                Text(snapshot.hideAmounts
                     ? WidgetFormat.percent(used) + " usado"
                     : WidgetFormat.money(derived.spentCents, hidden: false) + " · " + WidgetFormat.percent(used))
                    .font(.headline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .privacySensitive()
                Gauge(value: min(used, 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            } else {
                Text(WidgetFormat.money(derived.spentCents, hidden: snapshot.hideAmounts))
                    .font(.headline)
                    .privacySensitive()
                Text("Hoy " + WidgetFormat.money(derived.todayCents, hidden: snapshot.hideAmounts))
                    .font(.caption2)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
