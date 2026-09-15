import SwiftUI
import WidgetKit

// MARK: - Registro rápido

/// Los botones abren la app con un enlace: el widget no puede escribir en la
/// base (ver `WidgetSnapshot`), y así el registro pasa por el bloqueo de la app.
struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.quickAdd, provider: SnapshotProvider()) { entry in
            QuickAddView(entry: entry)
                .widgetBackground()
        }
        .configurationDisplayName("Registro rápido")
        .description("Tus gastos rápidos a un toque, y un atajo para anotar gasto o ingreso.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickAddView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { entry.snapshot?.theme.accent(scheme) ?? .blue }

    var body: some View {
        if family == .systemSmall {
            small
        } else {
            medium
        }
    }

    /// En pequeño iOS no admite varios enlaces: todo el widget abre el formulario.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(accent, in: Circle())
                .widgetAccentable()
            Spacer(minLength: 0)
            Text("Anotar gasto")
                .font(.headline)
            if let d = entry.derived, let snapshot = entry.snapshot {
                Text("Hoy " + WidgetFormat.money(d.todayCents, hidden: snapshot.hideAmounts))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(AppDeepLink.add(isIncome: false, source: nil).url)
    }

    private var medium: some View {
        let quick = entry.snapshot?.quickActions ?? []

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Registro rápido")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let d = entry.derived, let snapshot = entry.snapshot {
                    Text("Hoy " + WidgetFormat.money(d.todayCents, hidden: snapshot.hideAmounts))
                        .font(.caption.weight(.semibold))
                        .privacySensitive()
                }
            }

            if quick.isEmpty {
                HStack(spacing: 8) {
                    bigLink("Gasto", icon: "arrow.up.right", link: .add(isIncome: false, source: nil), tint: accent)
                    bigLink("Ingreso", icon: "arrow.down.left", link: .add(isIncome: true, source: nil),
                            tint: Color(hex: entry.snapshot?.theme.incomeHex ?? "248A3D"))
                }
                Text("Guarda un gasto como rápido en el formulario y aparecerá aquí.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: 8) {
                    ForEach(quick.prefix(3)) { item in
                        Link(destination: AppDeepLink.quick(item.id).url) {
                            VStack(spacing: 4) {
                                QuickIcon(name: item.icon, tint: accent, size: 30)
                                Text(item.label)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                Text(WidgetFormat.money(item.amountCents, hidden: false))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    VStack(spacing: 6) {
                        smallLink(icon: "arrow.up.right", link: .add(isIncome: false, source: nil), tint: accent)
                        smallLink(icon: "arrow.down.left", link: .add(isIncome: true, source: nil),
                                  tint: Color(hex: entry.snapshot?.theme.incomeHex ?? "248A3D"))
                    }
                    .frame(width: 40)
                }
            }
        }
    }

    private func bigLink(_ title: String, icon: String, link: AppDeepLink, tint: Color) -> some View {
        Link(destination: link.url) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .widgetAccentable()
        }
    }

    private func smallLink(icon: String, link: AppDeepLink, tint: Color) -> some View {
        Link(destination: link.url) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .widgetBackground()
        }
        .configurationDisplayName("Panel del mes")
        .description("Gasto, ingresos, ritmo, categorías y lo que tienes pendiente.")
        .supportedFamilies([.systemLarge])
    }
}

struct MonthPanelView: View {
    let entry: SnapshotEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let snapshot = entry.snapshot, let d = entry.derived {
            let hidden = snapshot.hideAmounts
            VStack(alignment: .leading, spacing: 10) {
                header(snapshot, d, hidden: hidden)

                if let used = d.usedFraction, let status = d.status {
                    VStack(alignment: .leading, spacing: 4) {
                        PaceBar(used: used, expected: d.expectedFraction,
                                tint: status == .ok ? snapshot.theme.accent(scheme) : status.color)
                        Text(WidgetFormat.percent(used) + " usado · " + WidgetFormat.percent(d.expectedFraction) + " del mes")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                MonthCurve(snapshot: snapshot, derived: d)
                    .frame(height: 70)

                CategoryBars(snapshot: snapshot, derived: d, date: entry.date, limit: 3)

                Divider()
                attention(snapshot, hidden: hidden)
            }
        } else {
            EmptySnapshotView()
        }
    }

    private func header(_ snapshot: WidgetSnapshot, _ d: WidgetDerived, hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(WidgetFormat.monthName(entry.date))
                    .font(.headline)
                Spacer()
                Text(WidgetFormat.money(d.spentCents, hidden: hidden))
                    .font(.title2.weight(.bold))
                    .privacySensitive()
                if let change = d.changeVsPrevious {
                    Text(WidgetFormat.change(change))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(change > 0 ? Color.orange : Color.green)
                }
            }
            if let income = d.incomeCents, let balance = d.balanceCents {
                Text("Ingresos " + WidgetFormat.money(income, hidden: hidden)
                     + " · Balance " + WidgetFormat.money(balance, hidden: hidden))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
            }
        }
    }

    private func attention(_ snapshot: WidgetSnapshot, hidden: Bool) -> some View {
        let a = snapshot.attention
        var items: [(icon: String, text: String, link: AppDeepLink)] = []
        if a.unclassifiedCount > 0 {
            items.append(("tray.full.fill", "\(a.unclassifiedCount) sin clasificar", .pending))
        }
        if a.debtCount > 0 {
            items.append(("person.2.fill", WidgetFormat.money(a.debtOutstandingCents, hidden: hidden) + " por cobrar", .summary))
        }
        if a.pendingRecurringCount > 0 {
            items.append(("repeat", "\(a.pendingRecurringCount) por confirmar", .summary))
        } else if let next = a.nextRecurring {
            items.append(("calendar", next.label + " " + WidgetFormat.relativeDay(next.date, from: entry.date), .summary))
        }

        return HStack(spacing: 12) {
            if items.isEmpty {
                Label("Todo al día", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                    Link(destination: item.link.url) {
                        Label(item.text, systemImage: item.icon)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .privacySensitive()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
}
