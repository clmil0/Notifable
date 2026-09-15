import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Configuración

/// Una categoría elegible al configurar el widget. Sale del resumen, no de la
/// base: el widget nunca abre SwiftData.
struct WidgetCategoryEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Categoría"
    static var defaultQuery = WidgetCategoryQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct WidgetCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetCategoryEntity] {
        identifiers.map(WidgetCategoryEntity.init(id:))
    }

    /// Primero las que tienen límite: son las que tiene sentido vigilar.
    func suggestedEntities() async throws -> [WidgetCategoryEntity] {
        guard let snapshot = WidgetSnapshotStore.load() else { return [] }
        let withLimit = snapshot.limits.map(\.category)
        let rest = snapshot.categoryNames.filter { !withLimit.contains($0) }
        return (withLimit + rest).map(WidgetCategoryEntity.init(id:))
    }

    func defaultResult() async -> WidgetCategoryEntity? {
        WidgetSnapshotStore.load()?.limits.first.map { WidgetCategoryEntity(id: $0.category) }
    }
}

struct CategoryLimitConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Límite de categoría"
    static var description = IntentDescription("Elige qué categoría vigilar.")

    /// Sin elegir, el widget muestra el límite más cerca de pasarse.
    @Parameter(title: "Categoría")
    var category: WidgetCategoryEntity?
}

struct CategoryLimitEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let category: String?

    /// El límite elegido, o el más apretado si no se eligió ninguno.
    var limit: WidgetSnapshot.LimitSummary? {
        guard let snapshot else { return nil }
        if let category { return snapshot.limits.first { $0.category == category } }
        return snapshot.limits.first
    }
}

struct CategoryLimitProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategoryLimitEntry {
        CategoryLimitEntry(date: Date(), snapshot: .sample(), category: nil)
    }

    func snapshot(for configuration: CategoryLimitConfiguration, in context: Context) async -> CategoryLimitEntry {
        let preview = SnapshotTimeline.preview(in: context)
        return CategoryLimitEntry(date: preview.date, snapshot: preview.snapshot, category: configuration.category?.id)
    }

    func timeline(for configuration: CategoryLimitConfiguration, in context: Context) async -> Timeline<CategoryLimitEntry> {
        let entries = SnapshotTimeline.entries(snapshot: WidgetSnapshotStore.load()).map {
            CategoryLimitEntry(date: $0.date, snapshot: $0.snapshot, category: configuration.category?.id)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - Widget

struct CategoryLimitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.categoryLimit,
                               intent: CategoryLimitConfiguration.self,
                               provider: CategoryLimitProvider()) { entry in
            CategoryLimitView(entry: entry)
                .widgetURL(AppDeepLink.categories.url)
        }
        .configurationDisplayName("Límite de categoría")
        .description("Cuánto te queda en una categoría antes del corte.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct CategoryLimitView: View {
    let entry: CategoryLimitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, let limit = entry.limit, !limit.isStale(at: entry.date) {
            if family == .accessoryCircular {
                Gauge(value: min(limit.fraction, 1)) {
                    Image(systemName: limit.symbol)
                } currentValueLabel: {
                    Image(systemName: limit.symbol)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .containerBackground(for: .widget) { Color.clear }
            } else {
                LimitCard(limit: limit, hidden: snapshot.hideAmounts, date: entry.date)
                    .widgetBackground()
            }
        } else if family == .accessoryCircular {
            WidgetPenguin(entry.snapshot, monochrome: true)
                .padding(6)
                .containerBackground(for: .widget) { Color.clear }
        } else if let snapshot = entry.snapshot {
            let stale = entry.limit?.isStale(at: entry.date) == true
            PenguinMessage(snapshot: snapshot,
                           title: stale ? "Empezó un ciclo nuevo"
                                        : (entry.category.map { "\($0) sin límite" } ?? "Aún no tienes límites"),
                           subtitle: stale ? "Abre AgruPay para actualizarlo" : "Ponle uno en Categorías")
                .widgetBackground()
        } else {
            EmptySnapshotView().widgetBackground()
        }
    }
}

/// Categoría, lo que queda, días al corte y el límite en cinco tramos.
private struct LimitCard: View {
    let limit: WidgetSnapshot.LimitSummary
    let hidden: Bool
    let date: Date

    static let segments = 5

    var body: some View {
        let tint = limit.isOver ? WidgetPalette.over : WidgetPalette.amber
        let days = limit.daysLeft(at: date)
        let filled = limit.fraction <= 0 ? 0 : min(Self.segments, Int((limit.fraction * Double(Self.segments)).rounded(.up)))

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                QuickIcon(name: limit.symbol, tint: Color(hex: limit.colorHex), size: 22)
                Text(limit.category)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
            }

            Group {
                if hidden {
                    Text(WidgetFormat.percent(limit.fraction))
                } else if limit.isOver {
                    Text("−" + WidgetFormat.money(-limit.remainingCents, hidden: false))
                } else {
                    Text(WidgetFormat.money(limit.remainingCents, hidden: false))
                }
            }
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.9)
            .foregroundStyle(limit.isOver ? WidgetPalette.over : WidgetPalette.ink)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .privacySensitive()
            .contentTransition(.numericText())
            .padding(.top, 12)

            Text((limit.isOver ? "te pasaste · " : "para ") + (days == 1 ? "1 día" : "\(days) días"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
                .padding(.top, 3)

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                ForEach(0..<Self.segments, id: \.self) { index in
                    Capsule()
                        .fill(index < filled ? tint : WidgetPalette.track)
                        .frame(height: 6)
                }
            }
            .widgetAccentable()

            Text(WidgetFormat.percent(limit.fraction) + " del límite")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WidgetPalette.secondary)
                .lineLimit(1)
                .padding(.top, 7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
