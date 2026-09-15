import SwiftUI
import WidgetKit

// MARK: - Hoy

/// "Hoy": lo gastado hoy y cuánto puedes gastar por día sin pasarte.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.today, provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(AppDeepLink.summary.url)
                .widgetBackground()
        }
        .configurationDisplayName("Hoy")
        .description("Lo que llevas hoy y lo que te queda por día.")
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let snapshot = entry.snapshot, let d = entry.derived {
            let hidden = snapshot.hideAmounts
            if family == .accessoryInline {
                Text("Hoy " + WidgetFormat.money(d.todayCents, hidden: hidden))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("HOY", systemImage: "sun.max.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(snapshot.theme.accent(scheme))
                        .widgetAccentable()
                    Text(WidgetFormat.money(d.todayCents, hidden: hidden))
                        .font(.title.weight(.bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .privacySensitive()
                        .contentTransition(.numericText())

                    Spacer(minLength: 0)

                    if let perDay = d.availablePerDayCents {
                        caption("Te quedan", WidgetFormat.money(perDay, hidden: hidden) + " por día",
                                warn: d.todayCents > perDay)
                    } else if let remaining = d.remainingCents {
                        caption("Último día", "quedan " + WidgetFormat.money(remaining, hidden: hidden), warn: remaining == 0)
                    } else if d.elapsedDays > 0 {
                        caption("Promedio", WidgetFormat.money(d.spentCents / d.elapsedDays, hidden: hidden) + " por día",
                                warn: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if family == .accessoryInline {
            Text("AgruPay")
        } else {
            EmptySnapshotView()
        }
    }

    private func caption(_ title: String, _ value: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(warn ? Color.orange : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .privacySensitive()
        }
    }
}

// MARK: - Categorías

/// "Categorías": el total del mes y en qué se va.
struct CategoriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.categories, provider: SnapshotProvider()) { entry in
            CategoriesWidgetView(entry: entry)
                .widgetURL(AppDeepLink.categories.url)
                .widgetBackground()
        }
        .configurationDisplayName("¿A dónde va?")
        .description("Tu gasto del mes y las categorías que más pesan.")
        .supportedFamilies([.systemMedium])
    }
}

struct CategoriesWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let derived = entry.derived {
            HStack(alignment: .top, spacing: 16) {
                PaceSummary(snapshot: snapshot, derived: derived, date: entry.date)
                    .frame(maxWidth: 130)
                CategoryBars(snapshot: snapshot, derived: derived, date: entry.date, limit: 3)
            }
        } else {
            EmptySnapshotView()
        }
    }
}

/// Filas de categoría con barra proporcional al total del mes.
struct CategoryBars: View {
    let snapshot: WidgetSnapshot
    let derived: WidgetDerived
    let date: Date
    let limit: Int

    var body: some View {
        let hidden = snapshot.hideAmounts
        let total = max(1, snapshot.month.spentCents)
        let rows = derived.isCurrentMonth ? Array(snapshot.topCategories.prefix(limit)) : []

        VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Spacer()
                Text(derived.isCurrentMonth ? "Aún no hay gastos este mes" : "Mes nuevo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(rows) { row in
                    let share = Double(row.totalCents) / Double(total)
                    let isOver = snapshot.limits.contains { $0.category == row.name && $0.isOver && !$0.isStale(at: date) }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: row.symbol)
                                .font(.caption2)
                                .foregroundStyle(Color(hex: row.colorHex))
                                .frame(width: 14)
                                .widgetAccentable()
                            Text(row.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(hidden ? WidgetFormat.percent(share) : WidgetFormat.money(row.totalCents, hidden: false))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .privacySensitive()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule()
                                    .fill(isOver ? Color.red : Color(hex: row.colorHex))
                                    .frame(width: max(4, geo.size.width * share))
                                    .widgetAccentable()
                            }
                        }
                        .frame(height: 5)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
