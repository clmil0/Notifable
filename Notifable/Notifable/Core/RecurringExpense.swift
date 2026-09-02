import Foundation
import SwiftData

/// Con qué frecuencia se repite un gasto.
enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case never = "Nunca"
    case weekly = "Cada semana"
    case monthly = "Cada mes"
    case yearly = "Cada año"

    var id: String { rawValue }
}

/// Plantilla de gasto que se repite en el tiempo.
///
/// Reemplaza al `Toggle("Es Suscripción")`, que sólo ponía `isSubscription = true`
/// en un gasto suelto: no programaba nada, no sabía cuándo tocaba el siguiente y
/// no aparecía en ninguna lista.
@Model
final class RecurringExpense {

    var id: UUID
    var merchant: String
    var category: String
    /// Monto esperado. Puede diferir del real; por eso existe la confirmación.
    var amount: Double
    var currency: String

    var frequencyRaw: String
    /// Para `.monthly` / `.yearly`: día del mes (1…31).
    var dayOfMonth: Int
    /// Para `.weekly`: días de la semana, 1 = domingo (convención de `Calendar`).
    var weekdays: [Int]

    /// Con `true` el gasto se inserta sin preguntar. Sólo tiene sentido si el
    /// monto nunca cambia (Netflix). Por defecto `false`.
    var autoConfirm: Bool

    var isPaused: Bool
    var startDate: Date
    var endDate: Date?

    /// Última fecha programada que ya se resolvió (confirmada, omitida o
    /// cumplida por el banco). Evita volver a proponer lo mismo.
    var lastResolvedOccurrence: Date?

    var createdAt: Date

    init(merchant: String,
         category: String,
         amount: Double,
         currency: String = "PEN",
         frequency: RecurrenceFrequency = .monthly,
         dayOfMonth: Int = 1,
         weekdays: [Int] = [],
         autoConfirm: Bool = false,
         startDate: Date = Date(),
         endDate: Date? = nil) {
        self.id = UUID()
        self.merchant = merchant
        self.category = category
        self.amount = Money.normalized(amount)
        self.currency = currency
        self.frequencyRaw = frequency.rawValue
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        self.weekdays = weekdays
        self.autoConfirm = autoConfirm
        self.isPaused = false
        self.startDate = startDate
        self.endDate = endDate
        self.lastResolvedOccurrence = nil
        self.createdAt = Date()
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    // MARK: - Fechas

    /// Fechas programadas dentro de un intervalo.
    ///
    /// **Día 31 en meses cortos:** se usa el último día disponible del mes, no
    /// se salta la ocurrencia. Un alquiler con vencimiento el 31 debe existir
    /// también en febrero.
    func occurrences(in interval: DateInterval) -> [Date] {
        guard !isPaused, frequency != .never else { return [] }
        let cal = Period.calendar
        let from = max(interval.start, cal.startOfDay(for: startDate))
        let until = endDate.map { min(interval.end, $0) } ?? interval.end
        guard from < until else { return [] }

        var result: [Date] = []
        switch frequency {
        case .never:
            break
        case .weekly:
            var cursor = cal.startOfDay(for: from)
            while cursor < until {
                if weekdays.contains(cal.component(.weekday, from: cursor)) {
                    result.append(cursor)
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        case .monthly:
            var cursor = cal.dateInterval(of: .month, for: from)?.start ?? from
            while cursor < until {
                if let date = clampedDay(dayOfMonth, inMonthOf: cursor),
                   date >= from, date < until {
                    result.append(date)
                }
                guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
                cursor = next
            }
        case .yearly:
            let startYear = cal.component(.year, from: from)
            let endYear = cal.component(.year, from: until)
            let month = cal.component(.month, from: startDate)
            for year in startYear...max(startYear, endYear) {
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = 1
                guard let monthStart = cal.date(from: comps),
                      let date = clampedDay(dayOfMonth, inMonthOf: monthStart),
                      date >= from, date < until else { continue }
                result.append(date)
            }
        }
        return result.sorted()
    }

    private func clampedDay(_ day: Int, inMonthOf reference: Date) -> Date? {
        let cal = Period.calendar
        guard let range = cal.range(of: .day, in: .month, for: reference) else { return nil }
        var comps = cal.dateComponents([.year, .month], from: reference)
        comps.day = min(day, range.count)
        comps.hour = 9
        return cal.date(from: comps)
    }

    /// Próxima fecha programada a partir de hoy.
    var nextOccurrence: Date? {
        let cal = Period.calendar
        let from = cal.startOfDay(for: Date())
        guard let horizon = cal.date(byAdding: .year, value: 2, to: from) else { return nil }
        return occurrences(in: DateInterval(start: from, end: horizon)).first
    }

    /// Aporte al total mensual comprometido, en la moneda de la regla.
    /// Semanal se prorratea con 52/12 semanas, anual con 1/12.
    var monthlyEquivalent: Double {
        guard !isPaused, frequency != .never else { return 0 }
        switch frequency {
        case .never:   return 0
        case .weekly:  return Money.multiply(amount, by: Double(weekdays.count) * 52.0 / 12.0)
        case .monthly: return Money.normalized(amount)
        case .yearly:  return Money.multiply(amount, by: 1.0 / 12.0)
        }
    }

    /// Descripción legible: "Cada mes, día 5" / "Lun a vie".
    var scheduleLabel: String {
        guard frequency != .never else { return "No se repite" }
        switch frequency {
        case .never: return ""
        case .weekly:
            let names = [1: "dom", 2: "lun", 3: "mar", 4: "mié", 5: "jue", 6: "vie", 7: "sáb"]
            let sorted = weekdays.sorted()
            if sorted == [2, 3, 4, 5, 6] { return "Lun a vie" }
            if sorted.count == 7 { return "Todos los días" }
            return sorted.compactMap { names[$0] }.joined(separator: ", ").capitalizedFirst
        case .monthly:
            return "Cada mes, día \(dayOfMonth)"
        case .yearly:
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_PE")
            f.dateFormat = "d 'de' MMMM"
            return "Cada año, " + f.string(from: startDate)
        }
    }
}

/// Gasto guardado como atajo de un toque.
///
/// Resuelve lo que el parser de correos no ve: efectivo y Yape pequeños. El
/// caso real es el pasaje de S/ 2.50 — cinco pasos de formulario para dos soles
/// y medio significa que nadie lo registra y el mes queda subestimado.
@Model
final class QuickExpense {

    var id: UUID
    var label: String
    var merchant: String
    var category: String
    var amount: Double
    var currency: String
    /// Nombre de SF Symbol, o "yape"/"plin" para usar los assets.
    var iconName: String
    /// Orden en el modal. Los 3 primeros son los visibles.
    var sortIndex: Int
    var useCount: Int
    var lastUsedAt: Date?

    init(label: String,
         merchant: String,
         category: String,
         amount: Double,
         currency: String = "PEN",
         iconName: String = "bag.fill",
         sortIndex: Int = 0) {
        self.id = UUID()
        self.label = label
        self.merchant = merchant
        self.category = category
        self.amount = Money.normalized(amount)
        self.currency = currency
        self.iconName = iconName
        self.sortIndex = sortIndex
        self.useCount = 0
        self.lastUsedAt = nil
    }

    func makeExpense(date: Date = Date()) -> Expense {
        // El `init` del modelo lleva `date:` antes que `category:`.
        Expense(
            amount: Money.normalized(amount),
            merchant: merchant,
            date: date,
            category: category,
            isSubscription: false,
            currency: currency
        )
    }

    /// Atajos sugeridos a partir del historial: montos exactos que el usuario
    /// repite. Se ofrecen al configurar, no se crean solos.
    static func suggestions(from history: [Expense], limit: Int = 3) -> [(merchant: String, amount: Double, category: String, count: Int)] {
        let manual = history.filter { $0.category != Accounting.unclassified }
        let groups = Dictionary(grouping: manual) { expense in
            expense.merchant + "|" + String(Money.cents(expense.amount))
        }
        return groups.values
            .filter { $0.count >= 3 }
            .compactMap { group -> (String, Double, String, Int)? in
                guard let first = group.first else { return nil }
                return (first.merchant, first.amount, first.category, group.count)
            }
            .sorted { $0.3 > $1.3 }
            .prefix(limit)
            .map { (merchant: $0.0, amount: $0.1, category: $0.2, count: $0.3) }
    }
}
