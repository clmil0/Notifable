import SwiftUI

/// Presupuesto y ritmo de gasto.
///
/// El presupuesto se guarda **mensual** y se prorratea a la ventana visible por
/// número de días, así el mismo número tiene sentido en Día, Semana, Mes y Rango.
/// Si el usuario no registra ingresos, ésta es la única referencia que necesita
/// la app para responder "¿voy bien?".
///
/// **No es un `ObservableObject`.** `@AppStorage` es un `DynamicProperty`: dentro
/// de una vista se suscribe a `UserDefaults` y redibuja, pero dentro de una clase
/// sólo lee y escribe — no dispara `objectWillChange`, así que la pantalla se
/// quedaría con el presupuesto viejo hasta el siguiente redibujado por otra
/// causa. Las vistas declaran su propio `@AppStorage` con estas claves y aquí
/// vive únicamente el cálculo, que es puro.
enum BudgetStore {

    static let enabledKey = "budgetEnabled"
    static let monthlyBudgetKey = "monthlyBudget"
    static let tracksIncomeKey = "trackIncome"

    static func hasBudget(monthlyBudget: Double, enabled: Bool) -> Bool {
        enabled && Money.cents(monthlyBudget) > 0
    }

    /// Meta prorrateada al periodo visible. `nil` si no hay presupuesto: la
    /// tarjeta muestra un botón para definirlo en vez de inventarse una meta.
    static func target(monthlyBudget: Double, enabled: Bool, for period: Period) -> Double? {
        guard hasBudget(monthlyBudget: monthlyBudget, enabled: enabled) else { return nil }
        let cal = Period.calendar
        let daysInMonth = cal.range(of: .day, in: .month, for: period.reference)?.count ?? 30

        switch period.granularity {
        case .mes:
            return Money.normalized(monthlyBudget)
        case .anio:
            return Money.multiply(monthlyBudget, by: 12)
        case .dia, .semana, .rango:
            let perDay = Money.divide(monthlyBudget, by: daysInMonth)
            return Money.multiply(perDay, by: Double(period.totalDays))
        }
    }

    static func pace(monthlyBudget: Double, enabled: Bool, for period: Period, spent: Double) -> Pace? {
        guard let target = target(monthlyBudget: monthlyBudget, enabled: enabled, for: period) else { return nil }
        return Pace(period: period, spent: spent, target: target)
    }
}

/// Todo lo que la tarjeta principal necesita saber sobre el ritmo de gasto.
///
/// La idea: un monto grande solo dice cuánto llevas. Comparado con el ritmo
/// esperado del periodo, dice si vas bien. Eso es lo que convierte la cifra en
/// un juicio, y es el trabajo de este tipo.
struct Pace {

    let period: Period
    let spent: Double
    let target: Double

    /// 0…1+ del presupuesto consumido.
    var usedFraction: Double { Money.ratio(spent, to: target) ?? 0 }

    var usedPercent: Int { percent(usedFraction) }

    /// Fracción del periodo transcurrida: la marca blanca de la barra.
    var expectedFraction: Double { min(1, period.elapsedFraction) }

    var expectedPercent: Int { percent(expectedFraction) }

    /// Lo que "deberías" llevar gastado a estas alturas del periodo.
    var expectedSpent: Double { Money.multiply(target, by: expectedFraction) }

    /// Positivo = vas por encima del ritmo.
    var delta: Double { Money.subtract(spent, expectedSpent) }

    var isOverPace: Bool { Money.cents(delta) > 0 }

    /// Proyección de cierre si mantienes el ritmo actual.
    var projection: Double {
        let elapsed = period.elapsedFraction
        guard elapsed > 0, elapsed.isFinite else { return spent }
        return Money.multiply(spent, by: 1.0 / elapsed)
    }

    var willExceed: Bool { Money.cents(projection) > Money.cents(target) }

    var remaining: Double { Money.clampedToZero(Money.subtract(target, spent)) }

    /// Cuánto puedes gastar por día en lo que queda del periodo sin pasarte.
    /// `nil` el último día: no queda "por día" que repartir.
    var availablePerDay: Double? {
        let days = period.remainingDays
        guard days > 0 else { return nil }
        return Money.divide(remaining, by: days)
    }

    var averagePerDay: Double {
        Money.divide(spent, by: max(1, period.elapsedDays))
    }

    /// La frase de la tarjeta. Sin métricas sueltas: una lectura y una consecuencia.
    var message: String {
        if Money.isZero(spent) {
            return "Aún no registras gastos en este periodo."
        }
        let direction = isOverPace ? "arriba" : "bajo"
        return "Vas " + Money.format(abs(delta)) + " " + direction + " de tu ritmo. "
            + "A este paso cierras en " + Money.format(projection) + "."
    }

    enum Status { case ok, warning, over }

    var status: Status {
        if Money.cents(spent) > Money.cents(target) { return .over }
        if isOverPace { return .warning }
        return .ok
    }

    /// Redondeo seguro a entero: una fracción infinita o NaN no debe llegar
    /// nunca a `Int(...)`, que en Swift es un crash, no un cero.
    private func percent(_ fraction: Double) -> Int {
        let scaled = (fraction * 100).rounded()
        guard scaled.isFinite else { return 0 }
        return Int(max(0, min(scaled, 100_000)))
    }
}
