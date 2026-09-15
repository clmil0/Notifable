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

/// La paleta crema de `Widgets AgruPay.dc.html`. Siempre la clara, también con
/// el teléfono en modo oscuro: el widget se ve igual en los dos.
enum WidgetPalette {
    static let background = Color(hex: "FDF8F0")
    static let ink = Color(hex: "2B2621")
    /// Las etiquetas en versalitas ("HOY TE QUEDAN").
    static let label = Color(hex: "7A5F2C")
    static let secondary = Color(hex: "6B6056")
    static let track = Color(hex: "EADFCB")
    static let idleBar = Color(hex: "E4D9C6")
    static let amber = Color(hex: "C88A2E")
    static let tile = Color(hex: "F4EADA")
    static let curve = Color(hex: "F7EFE2")
    static let incomeTile = Color(hex: "DCE8DD")
    static let income = Color(hex: "2F6640")
    static let over = Color(hex: "C2452D")
    /// El pingüino dorado de StandBy.
    static let standByGold = Color(hex: "E8B25C")
}

extension WidgetDerived.Status {
    var color: Color {
        switch self {
        case .ok, .warning: return WidgetPalette.amber
        case .over: return WidgetPalette.over
        }
    }

    var mood: PenguinMood {
        switch self {
        case .ok: return .ok
        case .warning: return .warning
        case .over: return .over
        }
    }

    /// Para StandBy, en versalitas.
    var headline: String {
        switch self {
        case .ok: return "Vas bien"
        case .warning: return "Vas un poco rápido"
        case .over: return "Presupuesto pasado"
        }
    }
}

extension WidgetDerived {
    var mood: PenguinMood { status?.mood ?? .ok }

    /// "Vas 12 % arriba del ritmo": lo gastado contra lo esperado a hoy.
    func paceLine(hidden: Bool) -> String? {
        guard let target = targetCents, let status else { return nil }
        if status == .over {
            return "Pasaste por " + WidgetFormat.money(spentCents - target, hidden: hidden)
        }
        let expected = Double(target) * expectedFraction
        guard expected > 0 else { return nil }
        let diff = Int(((Double(spentCents) / expected - 1) * 100).rounded())
        if diff == 0 { return "Vas justo al ritmo" }
        return "Vas \(min(abs(diff), 999)) % " + (diff > 0 ? "arriba" : "debajo") + " del ritmo"
    }
}

// MARK: - Pingüino

/// Tu pingüino de Amigos (`PenguinView`, el mismo de la app). Fuera de color
/// completo — teñido, transparente, pantalla bloqueada — pasa a silueta.
struct WidgetPenguin: View {
    let look: PenguinLook
    var mood: PenguinMood = .ok
    var forceMonochrome = false
    @Environment(\.widgetRenderingMode) private var renderingMode

    init(_ snapshot: WidgetSnapshot?, mood: PenguinMood = .ok, monochrome: Bool = false) {
        look = snapshot?.penguin ?? PenguinLook()
        self.mood = mood
        forceMonochrome = monochrome
    }

    var body: some View {
        PenguinView(look: look, mood: mood, monochrome: forceMonochrome || renderingMode != .fullColor)
            .accessibilityHidden(true)
    }
}

/// El pingüino que se asoma en una esquina cuando hay datos: nunca carga
/// información, así que va en el fondo y desaparece con él.
struct CornerPenguin {
    let snapshot: WidgetSnapshot?
    let mood: PenguinMood
    var size: CGFloat = 58
    var opacity: Double = 0.9
}

private struct WidgetCanvas: View {
    let corner: CornerPenguin?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WidgetPalette.background
            if let corner {
                WidgetPenguin(corner.snapshot, mood: corner.mood)
                    .frame(width: corner.size, height: corner.size)
                    .opacity(corner.opacity)
                    .offset(x: corner.size * 0.17, y: corner.size * 0.21)
            }
        }
    }
}

// MARK: - Piezas comunes

/// "HOY TE QUEDAN", "SETIEMBRE": la etiqueta de cada widget.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(WidgetPalette.label)
            .lineLimit(1)
            .widgetAccentable()
    }
}

/// Barra del presupuesto con la marca de ritmo: la misma idea que
/// `BudgetHeroCard`. Si el relleno pasa la marca, vas rápido.
struct PaceBar: View {
    let used: Double
    let expected: Double
    let tint: Color
    var track: Color = WidgetPalette.track
    var marker: Color = WidgetPalette.ink
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, width * min(max(used, 0), 1)))
                    .widgetAccentable()
                RoundedRectangle(cornerRadius: 1)
                    .fill(marker)
                    .frame(width: 2, height: height + 6)
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
    /// `nil` = el mismo color del icono, muy suave.
    var background: Color? = nil

    var body: some View {
        Group {
            if name == "yape" || name == "plin" {
                Image(name + "_icon")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            } else {
                Image(systemName: name)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(background ?? tint.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                    .widgetAccentable()
            }
        }
    }
}

/// Sin datos: el pingüino es protagonista, con un título y una línea.
struct PenguinMessage: View {
    let snapshot: WidgetSnapshot?
    let title: String
    var subtitle: String? = nil
    var mood: PenguinMood = .ok
    /// Pingüino a la izquierda y texto al lado (medium).
    var horizontal = false

    var body: some View {
        if horizontal {
            HStack(spacing: 16) {
                WidgetPenguin(snapshot, mood: mood)
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WidgetPalette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 9) {
                WidgetPenguin(snapshot, mood: mood)
                    .frame(width: 54, height: 54)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WidgetPalette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetPalette.secondary)
                        .privacySensitive()
                }
            }
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Sin resumen todavía: la app nunca se abrió desde que se instaló el widget.
struct EmptySnapshotView: View {
    var horizontal = false

    var body: some View {
        PenguinMessage(snapshot: nil, title: "Abre AgruPay para ver tu resumen", horizontal: horizontal)
    }
}

extension View {
    /// Fondo crema del diseño. En los modos teñido y transparente, y en
    /// StandBy, el sistema lo quita — y con él al pingüino de la esquina.
    ///
    /// Fija el esquema claro: la paleta ya no cambia, pero así tampoco lo hacen
    /// las piezas del sistema (gráficos, `ProgressView`, colores semánticos).
    func widgetBackground(_ corner: CornerPenguin? = nil) -> some View {
        containerBackground(for: .widget) { WidgetCanvas(corner: corner) }
            .environment(\.colorScheme, .light)
    }
}
