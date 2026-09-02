import Foundation

/// Lo que Ritmo responde, calculado aparte de la vista.
///
/// Tendencias mostraba un balance acumulado: una línea que sube y baja y que
/// nadie sabe leer. Ritmo contesta tres preguntas concretas —cuánto gastas al
/// día, si eso es más o menos que antes, y de dónde viene la diferencia— en
/// lenguaje natural. El cálculo vive aquí para poder probarlo sin pantalla.
struct Rhythm {

    let period: Period
    let current: PeriodTotals
    let previous: PeriodTotals

    // MARK: - Promedios

    /// Gasto medio por día transcurrido del periodo visible.
    var averagePerDay: Double { current.averagePerDay }

    /// El del periodo anterior, ya cerrado: se reparte entre todos sus días.
    var previousAveragePerDay: Double {
        Money.divide(previous.spent, by: max(1, previous.dailySpent.count))
    }

    /// Positivo = gastas más al día que en el periodo anterior.
    var dailyDelta: Double { Money.subtract(averagePerDay, previousAveragePerDay) }

    var hasComparison: Bool { !Money.isZero(previous.spent) }

    // MARK: - Titular

    /// "Gastas S/ 132 al día, S/ 21 más que en agosto."
    var headline: String {
        guard !Money.isZero(current.spent) else {
            return "Aún no has gastado nada en este periodo."
        }
        let base = "Gastas " + Money.format(averagePerDay) + " al día"
        guard hasComparison else { return base + "." }

        if Money.isZero(dailyDelta) {
            return base + ", igual que " + period.granularity.previousLabel + "."
        }
        let direction = Money.cents(dailyDelta) > 0 ? "más" : "menos"
        return base + ", " + Money.format(abs(dailyDelta)) + " " + direction
            + " que " + period.granularity.previousLabel + "."
    }

    /// "Casi todo el aumento viene de Comida (+S/ 148 en el mes)."
    var supportLine: String? {
        guard hasComparison, let top = categoryChanges.first, !Money.isZero(top.delta) else { return nil }
        let sign = Money.cents(top.delta) > 0 ? "+" : "−"
        let verb = Money.cents(top.delta) > 0 ? "aumento" : "ahorro"
        return "Casi todo el " + verb + " viene de " + top.category
            + " (" + sign + Money.format(abs(top.delta)) + " en el periodo)."
    }

    // MARK: - Cambio por categoría

    struct CategoryChange: Identifiable {
        let category: String
        let current: Double
        let previous: Double
        var delta: Double { Money.subtract(current, previous) }
        var id: String { category }
    }

    /// Categorías ordenadas por cuánto cambiaron, en valor absoluto.
    var categoryChanges: [CategoryChange] {
        var currentByCategory: [String: Double] = [:]
        for item in current.byCategory { currentByCategory[item.category] = item.total }
        var previousByCategory: [String: Double] = [:]
        for item in previous.byCategory { previousByCategory[item.category] = item.total }

        let names = Set(currentByCategory.keys).union(previousByCategory.keys)
        return names
            .map { CategoryChange(category: $0,
                                  current: currentByCategory[$0] ?? 0,
                                  previous: previousByCategory[$0] ?? 0) }
            .filter { !Money.isZero($0.delta) }
            .sorted {
                let l = abs(Money.cents($0.delta))
                let r = abs(Money.cents($1.delta))
                return l == r ? $0.category < $1.category : l > r
            }
    }

    /// El cambio más grande en valor absoluto, para escalar las barras.
    var largestChange: Double {
        categoryChanges.map { abs($0.delta) }.max() ?? 0
    }

    // MARK: - Días

    /// Sólo los días ya transcurridos: un mes a medias no tiene 18 "días sin
    /// gastar" porque aún no han llegado.
    var elapsedDays: [PeriodTotals.DayTotal] {
        Array(current.dailySpent.prefix(period.elapsedDays))
    }

    var daysWithoutSpending: Int {
        elapsedDays.filter { Money.isZero($0.total) }.count
    }

    var previousDaysWithoutSpending: Int {
        previous.dailySpent.filter { Money.isZero($0.total) }.count
    }

    /// Media de los días transcurridos, para la línea horizontal del gráfico.
    var averageOfElapsedDays: Double {
        Money.divide(current.spent, by: max(1, elapsedDays.count))
    }

    // MARK: - Agrupación del gráfico

    /// Una barra del gráfico. En un mes es un día; en un año, un mes.
    struct Bucket: Identifiable {
        let date: Date
        let total: Double
        let label: String
        let containsToday: Bool
        var id: Date { date }
    }

    /// Un año son 365 barras: con 3 pt de separación la fila mide más de mil
    /// puntos y revienta el ancho de la pantalla. Pasado cierto número de días
    /// el gráfico agrupa —por semana, y por mes en el año— en vez de intentar
    /// dibujar un día por barra.
    enum Grouping {
        case day, week, month

        var unitTitle: String {
            switch self {
            case .day: return "Día por día"
            case .week: return "Semana a semana"
            case .month: return "Mes a mes"
            }
        }

        var averageLabel: String {
            switch self {
            case .day: return "promedio diario"
            case .week: return "promedio semanal"
            case .month: return "promedio mensual"
            }
        }
    }

    var grouping: Grouping {
        switch period.granularity {
        case .anio: return .month
        case .dia, .semana: return .day
        case .mes, .rango: return period.totalDays > 45 ? .week : .day
        }
    }

    /// Las barras a dibujar, ya agrupadas y recortadas a lo transcurrido.
    var chartBuckets: [Bucket] {
        let cal = Period.calendar
        let days = elapsedDays

        switch grouping {
        case .day:
            return days.map {
                Bucket(date: $0.date,
                       total: $0.total,
                       label: "\(cal.component(.day, from: $0.date))",
                       containsToday: cal.isDateInToday($0.date))
            }
        case .week:
            return group(days, by: .weekOfYear) { start in
                "\(cal.component(.day, from: start))"
            }
        case .month:
            return group(days, by: .month) { start in
                let f = DateFormatter()
                f.locale = Locale(identifier: "es_PE")
                f.dateFormat = "MMM"
                return f.string(from: start).capitalizedFirst
            }
        }
    }

    /// Suma en céntimos por grupo, para no perder ni inventar nada al agrupar:
    /// la suma de las barras sigue siendo exactamente el gasto del periodo.
    private func group(_ days: [PeriodTotals.DayTotal],
                       by component: Calendar.Component,
                       label: (Date) -> String) -> [Bucket] {
        let cal = Period.calendar
        var cents: [Date: Int] = [:]
        var hasToday: Set<Date> = []
        var order: [Date] = []

        for day in days {
            guard let start = cal.dateInterval(of: component, for: day.date)?.start else { continue }
            if cents[start] == nil { order.append(start) }
            cents[start, default: 0] += Money.cents(day.total)
            if cal.isDateInToday(day.date) { hasToday.insert(start) }
        }

        return order.map { start in
            Bucket(date: start,
                   total: Money.value(cents[start] ?? 0),
                   label: label(start),
                   containsToday: hasToday.contains(start))
        }
    }

    /// Media por barra, para la línea horizontal. Con el gráfico agrupado tiene
    /// que ser la media del grupo, no la del día, o la línea queda al ras del suelo.
    var averagePerBucket: Double {
        Money.divide(current.spent, by: max(1, chartBuckets.count))
    }

    /// Día de la semana con mayor gasto medio.
    var busiestWeekday: (name: String, average: Double)? {
        let cal = Period.calendar
        var totals: [Int: Int] = [:]      // weekday -> céntimos
        var counts: [Int: Int] = [:]
        for day in elapsedDays {
            let weekday = cal.component(.weekday, from: day.date)
            totals[weekday, default: 0] += Money.cents(day.total)
            counts[weekday, default: 0] += 1
        }
        guard !totals.isEmpty else { return nil }

        let averages = totals.map { weekday, cents -> (Int, Int) in
            (weekday, cents / max(1, counts[weekday] ?? 1))
        }
        guard let top = averages.max(by: { $0.1 == $1.1 ? $0.0 > $1.0 : $0.1 < $1.1 }),
              top.1 > 0 else { return nil }

        return (name: Rhythm.weekdayName(top.0), average: Money.value(top.1))
    }

    static func weekdayName(_ weekday: Int) -> String {
        let names = ["", "Domingo", "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado"]
        guard names.indices.contains(weekday) else { return "—" }
        return names[weekday]
    }
}

/// Una suscripción detectada: mismo comercio, marcado `isSubscription`.
struct DetectedSubscription: Identifiable {
    let merchant: String
    let amount: Double
    /// Día del mes en que suele cobrarse.
    let dayOfMonth: Int
    var id: String { merchant }
}
