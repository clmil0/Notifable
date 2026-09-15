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
                .widgetBackground()
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
            } else {
                LimitCard(limit: limit, hidden: snapshot.hideAmounts, date: entry.date)
            }
        } else if family == .accessoryCircular {
            Image(systemName: "gauge.with.dots.needle.0percent")
        } else {
            NoLimitView(category: entry.category, hasSnapshot: entry.snapshot != nil,
                        stale: entry.limit?.isStale(at: entry.date) == true)
        }
    }
}

private struct LimitCard: View {
    let limit: WidgetSnapshot.LimitSummary
    let hidden: Bool
    let date: Date

    var body: some View {
        let tint = limit.isOver ? Color.red : (limit.isNear ? Color.orange : Color(hex: limit.colorHex))
        let days = limit.daysLeft(at: date)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(limit.category)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(days == 1 ? "1 día" : "\(days) días")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle().stroke(.quaternary, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(limit.fraction, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                VStack(spacing: 0) {
                    Image(systemName: limit.symbol)
                        .font(.caption)
                        .foregroundStyle(tint)
                    Text(WidgetFormat.percent(limit.fraction))
                        .font(.headline.weight(.bold))
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)

            Text(limit.isOver
                 ? "Pasado por " + WidgetFormat.money(-limit.remainingCents, hidden: hidden)
                 : "Quedan " + WidgetFormat.money(limit.remainingCents, hidden: hidden))
                .font(.caption2.weight(.medium))
                .foregroundStyle(limit.isOver ? Color.red : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .privacySensitive()
        }
    }
}

private struct NoLimitView: View {
    let category: String?
    let hasSnapshot: Bool
    let stale: Bool

    var body: some View {
        if !hasSnapshot {
            EmptySnapshotView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(stale ? "Empezó un ciclo nuevo" : (category.map { "\($0) no tiene límite" } ?? "Aún no tienes límites"))
                    .font(.caption.weight(.semibold))
                Text(stale ? "Abre AgruPay para actualizarlo." : "Ponle uno en Categorías.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
