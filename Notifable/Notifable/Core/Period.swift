import Foundation
import SwiftUI

/// Granularidad del periodo. Reemplaza a `DashboardFilter`.
enum PeriodGranularity: String, CaseIterable, Identifiable, Codable {
    case dia = "Día"
    case semana = "Semana"
    case mes = "Mes"
    case anio = "Año"
    case rango = "Rango"

    var id: String { rawValue }

    var shortLabel: String { rawValue }

    /// Unidad con la que avanza/retrocede la flecha.
    var navigationComponent: Calendar.Component {
        switch self {
        case .dia: return .day
        case .semana: return .weekOfYear
        case .mes: return .month
        case .anio: return .year
        case .rango: return .day
        }
    }

    /// Cómo se llama el periodo anterior en las comparaciones.
    var previousLabel: String {
        switch self {
        case .dia: return "ayer"
        case .semana: return "la semana pasada"
        case .mes: return "el mes pasado"
        case .anio: return "el año pasado"
        case .rango: return "el rango anterior"
        }
    }
}

/// El periodo visible: una sola fuente de verdad para las tres pestañas.
///
/// Antes cada vista tenía su propio `@AppStorage` de filtro + su propio
/// `referenceDate` + su propia lógica de intervalos duplicada tres veces
/// (`syncFilters` existía para intentar mantenerlos a la par). Ahora el periodo
/// es un valor navegable, se guarda una sola vez y las vistas sólo lo leen.
struct Period: Equatable, Hashable {

    var granularity: PeriodGranularity
    var reference: Date
    var customStart: Date
    var customEnd: Date

    init(granularity: PeriodGranularity = .mes,
         reference: Date = Date(),
         customStart: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
         customEnd: Date = Date()) {
        self.granularity = granularity
        self.reference = reference
        self.customStart = customStart
        self.customEnd = customEnd
    }

    /// Lunes como primer día de la semana (Perú).
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "es_PE")
        c.timeZone = .current
        return c
    }

    // MARK: - Intervalo

    /// Intervalo semiabierto `[start, end)`.
    ///
    /// **Corrección contable (ACCOUNTING.md §1):** el código anterior filtraba
    /// con `date >= interval.start && date <= interval.end`. `interval.end` es
    /// el inicio del periodo siguiente, así que un movimiento registrado
    /// exactamente a las 00:00:00 —el caso de los correos de banco cuyo parser
    /// deja la hora en cero— se contaba en dos periodos a la vez.
    /// Aquí el extremo derecho es exclusivo.
    var interval: DateInterval {
        let cal = Period.calendar
        switch granularity {
        case .dia:
            let start = cal.startOfDay(for: reference)
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .semana:
            return cal.dateInterval(of: .weekOfYear, for: reference)
                ?? DateInterval(start: reference, duration: 0)
        case .mes:
            return cal.dateInterval(of: .month, for: reference)
                ?? DateInterval(start: reference, duration: 0)
        case .anio:
            return cal.dateInterval(of: .year, for: reference)
                ?? DateInterval(start: reference, duration: 0)
        case .rango:
            let start = cal.startOfDay(for: min(customStart, customEnd))
            let endDay = cal.startOfDay(for: max(customStart, customEnd))
            let end = cal.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: end)
        }
    }

    func contains(_ date: Date) -> Bool {
        let i = interval
        return date >= i.start && date < i.end
    }

    /// Mismo periodo, corrido una unidad atrás. Base de todas las comparaciones.
    var previous: Period {
        var copy = self
        if granularity == .rango {
            let cal = Period.calendar
            let span = max(1, cal.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
            let newEnd = cal.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start
            copy.customEnd = newEnd
            copy.customStart = cal.date(byAdding: .day, value: -(span - 1), to: newEnd) ?? newEnd
            return copy
        }
        copy.reference = Period.calendar.date(
            byAdding: granularity.navigationComponent, value: -1, to: reference
        ) ?? reference
        return copy
    }

    var next: Period {
        var copy = self
        if granularity == .rango {
            let cal = Period.calendar
            let span = max(1, cal.dateComponents([.day], from: interval.start, to: interval.end).day ?? 1)
            copy.customStart = cal.date(byAdding: .day, value: span, to: interval.start) ?? interval.start
            copy.customEnd = cal.date(byAdding: .day, value: span - 1, to: copy.customStart) ?? copy.customStart
            return copy
        }
        copy.reference = Period.calendar.date(
            byAdding: granularity.navigationComponent, value: 1, to: reference
        ) ?? reference
        return copy
    }

    /// No se navega al futuro: el periodo siguiente no puede empezar después de ahora.
    ///
    /// **Corrección (ACCOUNTING.md §12):** `DateNavigatorView` comparaba con una
    /// granularidad distinta a la que navegaba (en `.hoy` comparaba semanas), así
    /// que estando en lunes la flecha derecha quedaba muerta hasta la semana
    /// siguiente. Aquí se compara exactamente lo que se navega.
    var canGoForward: Bool {
        guard granularity != .rango else { return false }
        return next.interval.start <= Date()
    }

    var isCurrent: Bool { contains(Date()) }

    // MARK: - Días del periodo (para el scrubber y los gráficos)

    var days: [Date] {
        let cal = Period.calendar
        var result: [Date] = []
        var cursor = cal.startOfDay(for: interval.start)
        while cursor < interval.end {
            result.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// El mismo día como periodo propio. Lo usa el scrubber al tocar una barra.
    func day(_ date: Date) -> Period {
        Period(granularity: .dia, reference: date, customStart: customStart, customEnd: customEnd)
    }

    /// Días ya transcurridos (incluye hoy). Base del "ritmo esperado".
    var elapsedDays: Int {
        let cal = Period.calendar
        let now = Date()
        guard interval.start <= now else { return 0 }
        if interval.end <= now { return days.count }
        let d = cal.dateComponents([.day], from: interval.start, to: cal.startOfDay(for: now)).day ?? 0
        return max(1, d + 1)
    }

    var totalDays: Int { max(1, days.count) }

    var remainingDays: Int { max(0, totalDays - elapsedDays) }

    /// Fracción del periodo ya transcurrida, 0…1.
    var elapsedFraction: Double {
        Double(elapsedDays) / Double(totalDays)
    }

    // MARK: - Etiquetas

    var title: String {
        let cal = Period.calendar
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.calendar = cal

        switch granularity {
        case .dia:
            if cal.isDateInToday(reference) { return "Hoy" }
            if cal.isDateInYesterday(reference) { return "Ayer" }
            f.dateFormat = "EEEE d 'de' MMMM"
            return f.string(from: reference).capitalizedFirst
        case .semana:
            let i = interval
            let last = cal.date(byAdding: .day, value: -1, to: i.end) ?? i.end
            f.dateFormat = "d"
            let startDay = f.string(from: i.start)
            f.dateFormat = "d MMM"
            let endDay = f.string(from: last)
            return "Sem. " + startDay + "–" + endDay
        case .mes:
            f.dateFormat = "MMMM yyyy"
            return f.string(from: reference).capitalizedFirst
        case .anio:
            f.dateFormat = "yyyy"
            return f.string(from: reference)
        case .rango:
            f.dateFormat = "d MMM"
            return f.string(from: min(customStart, customEnd)) + " – " + f.string(from: max(customStart, customEnd))
        }
    }

    /// Nombre del mes en español, con mayúscula inicial — "Septiembre".
    ///
    /// `Date.formatted(.dateTime.month(.wide))` usa el locale del sistema, que
    /// en un iPhone configurado en inglés devuelve "September": la app habla
    /// siempre en español, así que el mes no puede depender de eso.
    static func spanishMonthName(for date: Date, abbreviated: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.calendar = Period.calendar
        f.dateFormat = abbreviated ? "MMM" : "MMMM"
        return f.string(from: date).capitalizedFirst
    }

    /// Etiqueta corta para chips y encabezados de tarjeta.
    var shortTitle: String {
        switch granularity {
        case .mes:
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_PE")
            f.dateFormat = "MMM yyyy"
            return f.string(from: reference).capitalizedFirst
        default:
            return title
        }
    }

    /// "GASTADO ESTE MES" / "GASTADO ESTA SEMANA" / …
    var spentHeadline: String {
        switch granularity {
        case .dia: return isCurrent ? "GASTADO HOY" : "GASTADO ESE DÍA"
        case .semana: return isCurrent ? "GASTADO ESTA SEMANA" : "GASTADO ESA SEMANA"
        case .mes: return isCurrent ? "GASTADO ESTE MES" : "GASTADO ESE MES"
        case .anio: return isCurrent ? "GASTADO ESTE AÑO" : "GASTADO ESE AÑO"
        case .rango: return "GASTADO EN EL RANGO"
        }
    }
}

// MARK: - Persistencia

/// `@AppStorage("period")` guarda el periodo completo en una sola clave.
/// **Uno solo para toda la app**: al cambiar de pestaña el periodo se conserva.
///
/// La codificación es manual (`granularidad|ref|inicio|fin`) y deliberadamente
/// no usa `Codable`: un `struct` que conforma a la vez `Codable` y
/// `RawRepresentable where RawValue == String` toma la implementación por
/// defecto de la librería estándar, que codifica *a través de* `rawValue` — y si
/// `rawValue` a su vez codifica, la llamada se muerde la cola.
extension Period: RawRepresentable {

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              let granularity = PeriodGranularity(rawValue: parts[0]),
              let reference = TimeInterval(parts[1]),
              let start = TimeInterval(parts[2]),
              let end = TimeInterval(parts[3]) else { return nil }
        self.init(granularity: granularity,
                  reference: Date(timeIntervalSince1970: reference),
                  customStart: Date(timeIntervalSince1970: start),
                  customEnd: Date(timeIntervalSince1970: end))
    }

    var rawValue: String {
        [granularity.rawValue,
         String(reference.timeIntervalSince1970),
         String(customStart.timeIntervalSince1970),
         String(customEnd.timeIntervalSince1970)].joined(separator: "|")
    }
}

extension Period {

    /// Migración del `dashboardFilter` guardado por la versión anterior.
    ///
    /// Se ejecuta una vez en el primer arranque: traduce el filtro viejo
    /// (`Hoy`/`Semana`/`Mes`/`Rango`) a una granularidad y borra las claves que
    /// ya no existen (`dashboardFilter`, `categoriesFilter`, `syncFilters`).
    static func migrateLegacyFilterIfNeeded(defaults: UserDefaults = .standard) {
        let migratedKey = "didMigratePeriod"
        guard !defaults.bool(forKey: migratedKey) else { return }
        defer { defaults.set(true, forKey: migratedKey) }

        let legacy = defaults.string(forKey: "dashboardFilter")
            ?? defaults.string(forKey: "categoriesFilter")

        let granularity: PeriodGranularity
        switch legacy {
        case "Hoy": granularity = .dia
        case "Semana": granularity = .semana
        case "Rango": granularity = .rango
        case "Mes": granularity = .mes
        default: granularity = .mes
        }

        if defaults.string(forKey: "period") == nil {
            defaults.set(Period(granularity: granularity).rawValue, forKey: "period")
        }

        for dead in ["dashboardFilter", "categoriesFilter", "syncFilters"] {
            defaults.removeObject(forKey: dead)
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
