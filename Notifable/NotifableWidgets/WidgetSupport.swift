import SwiftUI
import WidgetKit

// MARK: - Timeline

/// Una entrada: la fecha que pinta y el resumen del que salen las cifras.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// `nil` = la app aún no escribió nada (recién instalada, o sin App Group).
    let snapshot: WidgetSnapshot?

    var derived: WidgetDerived? { snapshot.map { WidgetDerived($0, at: date) } }
}

enum SnapshotTimeline {

    /// Ahora y las dos medianoches siguientes. Las cifras sólo cambian por
    /// fecha a medianoche ("hoy", días restantes); todo lo demás llega con una
    /// recarga pedida por la app al guardar. Si la app no se abre en tres
    /// días, WidgetKit pide otra línea de tiempo al terminar ésta.
    static func entries(snapshot: WidgetSnapshot?, now: Date = Date()) -> [SnapshotEntry] {
        let cal = WidgetDerived.calendar
        var dates = [now]
        var cursor = cal.startOfDay(for: now)
        for _ in 0..<2 {
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            dates.append(next)
            cursor = next
        }
        return dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
    }

    static func placeholder() -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .sample())
    }

    /// En la galería se muestra el ejemplo si todavía no hay datos reales.
    static func preview(in context: TimelineProviderContext) -> SnapshotEntry {
        let stored = WidgetSnapshotStore.load()
        return SnapshotEntry(date: Date(), snapshot: context.isPreview ? (stored ?? .sample()) : stored)
    }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { SnapshotTimeline.placeholder() }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotTimeline.preview(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entries = SnapshotTimeline.entries(snapshot: WidgetSnapshotStore.load())
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Formato

enum WidgetFormat {

    /// "S/ 1,240" sin céntimos a partir de 100 soles: en un widget los
    /// céntimos de un total grande sólo quitan espacio. Debajo de 100 sí
    /// importan (el pasaje de S/ 2.50).
    static func money(_ cents: Int, hidden: Bool) -> String {
        guard !hidden else { return "S/ •••" }
        let value = Double(cents) / 100
        let formatter = abs(cents) >= 100_00 ? whole : decimal
        return "S/ " + (formatter.string(from: NSNumber(value: value)) ?? "0")
    }

    /// "S/ 1.2 mil" para los espacios más chicos (pantalla bloqueada).
    static func compactMoney(_ cents: Int, hidden: Bool) -> String {
        guard !hidden else { return "S/ •••" }
        let value = Double(cents) / 100
        if abs(value) >= 1_000 {
            return "S/ " + (oneDecimal.string(from: NSNumber(value: value / 1_000)) ?? "0") + " mil"
        }
        return money(cents, hidden: false)
    }

    static func percent(_ fraction: Double) -> String {
        let scaled = (fraction * 100).rounded()
        guard scaled.isFinite else { return "0 %" }
        return "\(Int(max(0, min(scaled, 9_999)))) %"
    }

    /// "▲12 %" / "▼5 %". Sin signo si la diferencia redondea a cero.
    static func change(_ fraction: Double) -> String {
        let scaled = Int((fraction * 100).rounded())
        if scaled == 0 { return "= igual" }
        return (scaled > 0 ? "▲" : "▼") + "\(min(abs(scaled), 999)) %"
    }

    static func monthName(_ date: Date, abbreviated: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.calendar = WidgetDerived.calendar
        f.dateFormat = abbreviated ? "MMM" : "MMMM"
        let name = f.string(from: date).replacingOccurrences(of: ".", with: "")
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func previousMonthName(_ snapshot: WidgetSnapshot) -> String {
        let previous = WidgetDerived.calendar.date(byAdding: .month, value: -1, to: snapshot.month.start)
        return previous.map { monthName($0) } ?? "el mes pasado"
    }

    /// "hoy", "mañana" o "jue 18".
    static func relativeDay(_ date: Date, from now: Date) -> String {
        let cal = WidgetDerived.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return "hoy"
        case 1: return "mañana"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_PE")
            f.dateFormat = "EEE d"
            return f.string(from: date).replacingOccurrences(of: ".", with: "")
        }
    }

    private static let whole: NumberFormatter = formatter(fraction: 0)
    private static let decimal: NumberFormatter = formatter(fraction: 2)
    private static let oneDecimal: NumberFormatter = {
        let f = formatter(fraction: 1)
        f.minimumFractionDigits = 0
        return f
    }()

    private static func formatter(fraction: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")      // "1,240.50", como en la app
        f.minimumFractionDigits = fraction
        f.maximumFractionDigits = fraction
        return f
    }
}

// MARK: - Colores

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(clean, radix: 16) ?? 0x808080
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

extension WidgetSnapshot.Theme {
    func accent(_ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? accentDarkHex : accentHex)
    }
}

extension WidgetDerived.Status {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .over: return .red
        }
    }

    var label: String {
        switch self {
        case .ok: return "Vas bien"
        case .warning: return "Por encima del ritmo"
        case .over: return "Presupuesto pasado"
        }
    }
}

// MARK: - Piezas comunes

/// Barra del presupuesto con la marca de ritmo: la misma idea que
/// `BudgetHeroCard`. Si el relleno pasa la marca, vas rápido.
struct PaceBar: View {
    let used: Double
    let expected: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, width * min(max(used, 0), 1)))
                    .widgetAccentable()
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2, height: height + 4)
                    .offset(x: min(width - 2, max(0, width * expected - 1)))
            }
        }
        .frame(height: height)
    }
}

/// Icono de categoría o de gasto rápido: SF Symbol, o el logo de Yape/Plin.
struct QuickIcon: View {
    let name: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Group {
            if name == "yape" || name == "plin" {
                Image(name + "_icon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else {
                Image(systemName: name)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                    .widgetAccentable()
            }
        }
    }
}

/// Sin resumen todavía: la app nunca se abrió desde que se instaló el widget.
struct EmptySnapshotView: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(compact ? .body : .title3)
                .foregroundStyle(.secondary)
            Text("Abre AgruPay para ver tu resumen")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

extension View {
    /// Fondo del sistema: respeta el modo claro/oscuro y los modos teñido y
    /// transparente de la pantalla de inicio.
    func widgetBackground() -> some View {
        containerBackground(for: .widget) { Color(.systemBackground) }
    }
}
