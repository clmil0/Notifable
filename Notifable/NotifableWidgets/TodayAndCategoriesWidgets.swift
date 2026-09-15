import SwiftUI
import WidgetKit

// MARK: - Hoy

/// "Hoy": cuánto te queda para hoy, lo que llevas y la semana en barras.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.today, provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry)
                .widgetURL(AppDeepLink.summary.url)
        }
        .configurationDisplayName("Hoy")
        .description("Lo que te queda para hoy y lo que llevas.")
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryInline {
            if let snapshot = entry.snapshot, let d = entry.derived {
                Text("Hoy " + WidgetFormat.money(d.todayCents, hidden: snapshot.hideAmounts))
            } else {
                Text("AgruPay")
            }
        } else if let snapshot = entry.snapshot, let d = entry.derived {
            small(snapshot, d)
        } else {
            EmptySnapshotView().widgetBackground()
        }
    }

    /// Lo disponible para hoy: el "por día", o lo que queda el último día.
    private func available(_ d: WidgetDerived) -> Int? {
        d.availablePerDayCents ?? d.remainingCents
    }

    @ViewBuilder
    private func small(_ snapshot: WidgetSnapshot, _ d: WidgetDerived) -> some View {
        let hidden = snapshot.hideAmounts
        if !d.isCurrentMonth {
            PenguinMessage(snapshot: snapshot, title: "Mes nuevo",
                           subtitle: "Abre la app para empezar " + WidgetFormat.monthName(entry.date).lowercased())
                .widgetBackground()
        } else if d.todayCents == 0 {
            PenguinMessage(snapshot: snapshot, title: "Nada anotado hoy",
                           subtitle: available(d).map { "Tienes " + WidgetFormat.money($0, hidden: hidden) + " para hoy" },
                           mood: d.mood)
                .widgetBackground()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(available(d) == nil ? "Hoy llevas" : "Hoy te quedan")
                Text(WidgetFormat.money(available(d) ?? d.todayCents, hidden: hidden))
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(WidgetPalette.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .privacySensitive()
                    .contentTransition(.numericText())
                    .padding(.top, 9)

                Spacer(minLength: 0)

                WeekBars(daily: Array(snapshot.month.dailySpentCents.prefix(d.elapsedDays)))
                    .frame(width: 96, height: 30)

                Text(caption(d, hidden: hidden))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                    .padding(.top, 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetBackground(CornerPenguin(snapshot: snapshot, mood: d.mood))
        }
    }

    private func caption(_ d: WidgetDerived, hidden: Bool) -> String {
        if available(d) != nil {
            return "Llevas " + WidgetFormat.money(d.todayCents, hidden: hidden) + " hoy"
        }
        let average = d.elapsedDays > 0 ? d.spentCents / d.elapsedDays : 0
        return "Promedio " + WidgetFormat.money(average, hidden: hidden) + "/día"
    }
}

/// Los últimos siete días en barras; hoy, la última, en ámbar.
struct WeekBars: View {
    let daily: [Int]

    var body: some View {
        let week = Array(daily.suffix(7))
        let days = Array(repeating: 0, count: 7 - week.count) + week
        let top = max(days.max() ?? 0, 1)

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, cents in
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == days.count - 1 ? WidgetPalette.amber : WidgetPalette.idleBar)
                            .frame(height: max(3, geo.size.height * Double(cents) / Double(top)))
                    }
                }
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Categorías

/// "¿A dónde va?": el total del mes y en qué se va.
struct CategoriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.categories, provider: SnapshotProvider()) { entry in
            CategoriesWidgetView(entry: entry)
                .widgetURL(AppDeepLink.categories.url)
        }
        .configurationDisplayName("¿A dónde va?")
        .description("Tu gasto del mes y las categorías que más pesan.")
        .supportedFamilies([.systemMedium])
    }
}

struct CategoriesWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let d = entry.derived {
            if !d.isCurrentMonth {
                PenguinMessage(snapshot: snapshot, title: "Mes nuevo",
                               subtitle: "Abre la app para empezar " + WidgetFormat.monthName(entry.date).lowercased() + ".",
                               horizontal: true)
                    .widgetBackground()
            } else if snapshot.topCategories.isEmpty {
                PenguinMessage(snapshot: snapshot, title: "Aún no hay gastos este mes",
                               subtitle: "Cuando anotes algo verás aquí en qué se va tu mes.",
                               horizontal: true)
                    .widgetBackground()
            } else {
                HStack(spacing: 18) {
                    summary(snapshot, d)
                        .frame(width: 118, alignment: .leading)
                    CategoryRows(snapshot: snapshot, date: entry.date, limit: 3, iconSize: 26, barHeight: 7)
                }
                .widgetBackground(CornerPenguin(snapshot: snapshot, mood: d.mood, size: 46, opacity: 0.85))
            }
        } else {
            EmptySnapshotView(horizontal: true).widgetBackground()
        }
    }

    private func summary(_ snapshot: WidgetSnapshot, _ d: WidgetDerived) -> some View {
        let hidden = snapshot.hideAmounts
        let top = snapshot.topCategories.first
        let share = top.map { Double($0.totalCents) / Double(max(1, snapshot.month.spentCents)) }

        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Se va en")
            Text(WidgetFormat.money(d.spentCents, hidden: hidden))
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(WidgetPalette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .privacySensitive()
                .contentTransition(.numericText())
            if let top, let share {
                Text("este mes · " + WidgetFormat.percent(share) + " en " + top.name.lowercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(2)
            }
        }
    }
}

/// Filas de categoría con icono y barra proporcional al total del mes.
struct CategoryRows: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let limit: Int
    var iconSize: CGFloat = 24
    var barHeight: CGFloat = 6

    var body: some View {
        let hidden = snapshot.hideAmounts
        let total = max(1, snapshot.month.spentCents)

        VStack(alignment: .leading, spacing: iconSize > 24 ? 11 : 10) {
            ForEach(snapshot.topCategories.prefix(limit)) { row in
                let share = Double(row.totalCents) / Double(total)
                let isOver = snapshot.limits.contains { $0.category == row.name && $0.isOver && !$0.isStale(at: date) }
                let tint = Color(hex: row.colorHex)
                HStack(spacing: 9) {
                    QuickIcon(name: row.symbol, tint: tint, size: iconSize)
                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WidgetPalette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(hidden ? WidgetFormat.percent(share) : WidgetFormat.money(row.totalCents, hidden: false))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(WidgetPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .privacySensitive()
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(WidgetPalette.track)
                                Capsule()
                                    .fill(isOver ? WidgetPalette.over : tint)
                                    .frame(width: max(barHeight, geo.size.width * min(share, 1)))
                                    .widgetAccentable()
                            }
                        }
                        .frame(height: barHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
