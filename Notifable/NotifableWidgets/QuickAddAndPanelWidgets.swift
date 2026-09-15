import SwiftUI
import WidgetKit

// MARK: - Registro rápido

/// Los botones abren la app con un enlace: el widget no puede escribir en la
/// base (ver `WidgetSnapshot`), y así el registro pasa por el bloqueo de la app.
/// Sin mascota: aquí cada centímetro es un botón.
struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.quickAdd, provider: SnapshotProvider()) { entry in
            QuickAddView(entry: entry)
                .widgetBackground()
        }
        .configurationDisplayName("Anota en un toque")
        .description("Tus gastos rápidos a un toque, y un atajo para anotar gasto o ingreso.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickAddView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemSmall {
            small
        } else {
            medium
        }
    }

    private var todayText: String? {
        guard let d = entry.derived, let snapshot = entry.snapshot else { return nil }
        return "Hoy " + WidgetFormat.money(d.todayCents, hidden: snapshot.hideAmounts)
    }

    /// En pequeño iOS no admite varios enlaces: todo el widget abre el formulario.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WidgetPalette.background)
                .frame(width: 44, height: 44)
                .background(WidgetPalette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .widgetAccentable()
            Spacer(minLength: 0)
            SectionLabel("Anota en un toque")
            Text("Anotar gasto")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WidgetPalette.ink)
                .padding(.top, 5)
            if let todayText {
                Text(todayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.secondary)
                    .privacySensitive()
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(AppDeepLink.add(isIncome: false, source: nil).url)
    }

    private var medium: some View {
        let quick = entry.snapshot?.quickActions ?? []

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Anota en un toque")
                Spacer()
                if let todayText {
                    Text(todayText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetPalette.secondary)
                        .privacySensitive()
                }
            }

            if quick.isEmpty {
                HStack(spacing: 9) {
                    bigLink("Gasto", icon: "plus", link: .add(isIncome: false, source: nil),
                            foreground: WidgetPalette.background, background: WidgetPalette.ink)
                    bigLink("Ingreso", icon: "arrow.down", link: .add(isIncome: true, source: nil),
                            foreground: WidgetPalette.income, background: WidgetPalette.incomeTile)
                }
                Text("Guarda un gasto como rápido en el formulario y aparecerá aquí.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: 9) {
                    ForEach(quick.prefix(3)) { item in
                        Link(destination: AppDeepLink.quick(item.id).url) {
                            VStack(spacing: 5) {
                                QuickIcon(name: item.icon, tint: WidgetPalette.label, size: 38,
                                          background: WidgetPalette.background)
                                Text(item.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.ink)
                                    .lineLimit(1)
                                Text(WidgetFormat.money(item.amountCents, hidden: false))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(WidgetPalette.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(WidgetPalette.tile, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    VStack(spacing: 8) {
                        smallLink(icon: "plus", link: .add(isIncome: false, source: nil),
                                  foreground: WidgetPalette.background, background: WidgetPalette.ink)
                        smallLink(icon: "arrow.down", link: .add(isIncome: true, source: nil),
                                  foreground: WidgetPalette.income, background: WidgetPalette.incomeTile)
                    }
                    .frame(width: 52)
                }
            }
        }
    }

    private func bigLink(_ title: String, icon: String, link: AppDeepLink,
                         foreground: Color, background: Color) -> some View {
        Link(destination: link.url) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .widgetAccentable()
        }
    }

    private func smallLink(icon: String, link: AppDeepLink, foreground: Color, background: Color) -> some View {
        Link(destination: link.url) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .widgetAccentable()
        }
    }
}

// MARK: - Panel del mes

struct MonthPanelWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.monthPanel, provider: SnapshotProvider()) { entry in
            MonthPanelView(entry: entry)
                .widgetURL(AppDeepLink.summary.url)
        }
        .configurationDisplayName("Panel del mes")
        .description("Gasto, ritmo, categorías y lo que tienes pendiente.")
        .supportedFamilies([.systemLarge])
    }
}

struct MonthPanelView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let snapshot = entry.snapshot, let d = entry.derived {
            let hidden = snapshot.hideAmounts
            VStack(alignment: .leading, spacing: 14) {
                header(snapshot, d, hidden: hidden)

                if let used = d.usedFraction, let status = d.status {
                    PaceBar(used: used, expected: d.expectedFraction, tint: status.color)
                }

                MonthCurve(snapshot: snapshot, derived: d)
                    .frame(height: 78)

                if d.isCurrentMonth, !snapshot.topCategories.isEmpty {
                    CategoryRows(snapshot: snapshot, date: entry.date, limit: 3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(d.isCurrentMonth ? "Aún no hay gastos este mes" : "Mes nuevo · abre la app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetPalette.secondary)
                }

                Spacer(minLength: 0)
                attention(snapshot, hidden: hidden)
            }
            .widgetBackground(CornerPenguin(snapshot: snapshot, mood: d.mood, size: 52, opacity: 0.5))
        } else {
            EmptySnapshotView().widgetBackground()
        }
    }

    private func header(_ snapshot: WidgetSnapshot, _ d: WidgetDerived, hidden: Bool) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(WidgetFormat.monthName(entry.date))
                Text(WidgetFormat.money(d.spentCents, hidden: hidden))
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(WidgetPalette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .privacySensitive()
                    .contentTransition(.numericText())
                    .padding(.top, 7)
                Group {
                    if let target = d.targetCents, let remaining = d.remainingCents {
                        Text("de " + WidgetFormat.money(target, hidden: hidden) + " · quedan " + WidgetFormat.money(remaining, hidden: hidden))
                    } else if let income = d.incomeCents, let balance = d.balanceCents {
                        Text("Ingresos " + WidgetFormat.money(income, hidden: hidden) + " · Balance " + WidgetFormat.money(balance, hidden: hidden))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .privacySensitive()
                .padding(.top, 4)
            }
            Spacer(minLength: 8)
            if let change = d.changeVsPrevious {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(WidgetFormat.change(change))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(change > 0 ? WidgetPalette.amber : WidgetPalette.income)
                    Text("vs. " + WidgetFormat.previousMonthName(snapshot).lowercased())
                        .font(.system(size: 10))
                        .foregroundStyle(WidgetPalette.secondary)
                }
            }
        }
    }

    /// Tres fichas: sin clasificar, por cobrar y el próximo recurrente.
    private func attention(_ snapshot: WidgetSnapshot, hidden: Bool) -> some View {
        let a = snapshot.attention
        var items: [(value: String, caption: String, link: AppDeepLink)] = []
        if a.unclassifiedCount > 0 {
            items.append(("\(a.unclassifiedCount)", "sin clasificar", .pending))
        }
        if a.debtCount > 0 {
            items.append((WidgetFormat.money(a.debtOutstandingCents, hidden: hidden), "por cobrar", .summary))
        }
        if a.pendingRecurringCount > 0 {
            items.append(("\(a.pendingRecurringCount)", "por confirmar", .summary))
        } else if let next = a.nextRecurring {
            items.append((WidgetFormat.relativeDay(next.date, from: entry.date), next.label, .summary))
        }

        return HStack(spacing: 7) {
            if items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WidgetPalette.income)
                    Text("Todo al día: nada sin clasificar ni por confirmar")
                        .foregroundStyle(WidgetPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WidgetPalette.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                    Link(destination: item.link.url) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.value)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(WidgetPalette.ink)
                                .privacySensitive()
                            Text(item.caption)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WidgetPalette.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WidgetPalette.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }
}
