import Foundation

/// Aritmética monetaria segura.
///
/// Regla del proyecto: **nunca** sumar, restar, acumular ni comparar dinero
/// directamente en `Double`. Todo monto se normaliza a céntimos enteros (`Int`),
/// se opera en enteros o `Decimal`, y sólo vuelve a `Double` para guardarse
/// en SwiftData o mostrarse en pantalla.
///
/// Motivo: `reduce(0) { $0 + $1.amount }` sobre `Double` acumula error de punto
/// flotante (0.1 + 0.2 == 0.30000000000000004). Con cientos de movimientos el
/// total del mes puede desviarse céntimos, y `(x * 100).rounded() / 100` sólo
/// arregla el valor individual, no la suma.
enum Money {

    // MARK: - Conversión base

    /// `Double` → céntimos enteros.
    ///
    /// Pasa por la **representación decimal más corta** del `Double`
    /// (`"\(value)"` da "1.005", no "1.00499999999999989…"). Es la diferencia
    /// entre redondear 1.005 a 1.01 —lo que el usuario escribió y lo que la
    /// pantalla muestra— y redondearlo a 1.00, que es lo que hace tanto
    /// `(x * 100).rounded() / 100` como `Decimal(x)`, porque ambos parten del
    /// valor binario exacto. Ver ACCOUNTING.md §8.
    static func cents(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let decimal = Decimal(string: "\(value)") ?? Decimal(value)
        var product = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 0, .plain)
        return Int(NSDecimalNumber(decimal: rounded).int64Value)
    }

    /// Céntimos enteros → `Double` con exactamente 2 decimales.
    static func value(_ cents: Int) -> Double {
        Double(cents) / 100.0
    }

    /// Normaliza a 2 decimales de forma estable.
    /// Sustituye a `(amount * 100).rounded() / 100` en los `init` de los modelos.
    static func normalized(_ value: Double) -> Double {
        self.value(cents(value))
    }

    // MARK: - Operaciones

    static func add(_ a: Double, _ b: Double) -> Double {
        value(cents(a) + cents(b))
    }

    static func subtract(_ a: Double, _ b: Double) -> Double {
        value(cents(a) - cents(b))
    }

    /// Suma de una colección acumulando en `Int`. Cero deriva por punto flotante.
    static func sum(_ values: [Double]) -> Double {
        value(values.reduce(0) { $0 + cents($1) })
    }

    /// Suma por clave: `Money.sum(expenses) { $0.amount }`
    static func sum<T>(_ items: [T], _ amount: (T) -> Double) -> Double {
        value(items.reduce(0) { $0 + cents(amount($1)) })
    }

    /// Multiplica dinero por un factor (tipo de cambio, porcentaje) con
    /// redondeo bancario sobre céntimos.
    static func multiply(_ value: Double, by factor: Double) -> Double {
        self.value(multiplyCents(cents(value), by: factor))
    }

    /// Núcleo entero de `multiply`: céntimos × factor → céntimos.
    /// Lo usa `Accounting` para convertir cada movimiento a soles una sola vez.
    static func multiplyCents(_ cents: Int, by factor: Double) -> Int {
        guard factor.isFinite else { return 0 }
        let decimalFactor = Decimal(string: "\(factor)") ?? Decimal(factor)
        var product = Decimal(cents) * decimalFactor
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 0, .bankers)
        return Int(NSDecimalNumber(decimal: rounded).int64Value)
    }

    /// Divide dinero entre un entero (promedios por día) con redondeo bancario.
    /// Preferible a `multiply(x, by: 1.0 / n)`, que arrastra el error de 1/3.
    static func divide(_ value: Double, by n: Int) -> Double {
        guard n != 0 else { return 0 }
        var quotient = Decimal(cents(value)) / Decimal(n)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .bankers)
        return self.value(Int(NSDecimalNumber(decimal: rounded).int64Value))
    }

    /// Razón entre dos montos. Devuelve `nil` en lugar de `NaN`/`inf`
    /// cuando el divisor es cero: obliga a decidir qué mostrar.
    static func ratio(_ a: Double, to b: Double) -> Double? {
        let divisor = cents(b)
        guard divisor != 0 else { return nil }
        return Double(cents(a)) / Double(divisor)
    }

    /// Porcentaje 0…100, o `nil` si el total es cero.
    static func percent(_ part: Double, of total: Double) -> Double? {
        guard let r = ratio(part, to: total) else { return nil }
        return r * 100
    }

    /// Nunca negativo (saldos pendientes, presupuesto restante).
    static func clampedToZero(_ value: Double) -> Double {
        cents(value) < 0 ? 0 : normalized(value)
    }

    /// Reparte un monto en `n` partes sin perder ni inventar céntimos.
    /// El resto se distribuye de a un céntimo entre las primeras partes.
    static func split(_ value: Double, into n: Int) -> [Double] {
        guard n > 0 else { return [] }
        let total = cents(value)
        let base = total / n
        let remainder = abs(total % n)
        let step = total < 0 ? -1 : 1
        return (0..<n).map { index in
            self.value(base + (index < remainder ? step : 0))
        }
    }

    // MARK: - Comparación

    static func isZero(_ value: Double) -> Bool { cents(value) == 0 }
    static func equals(_ a: Double, _ b: Double) -> Bool { cents(a) == cents(b) }
    static func isGreater(_ a: Double, than b: Double) -> Bool { cents(a) > cents(b) }

    // MARK: - Formato

    static let penFormatter: NumberFormatter = formatter(symbol: "S/ ")
    static let usdFormatter: NumberFormatter = formatter(symbol: "$ ")

    private static func formatter(symbol: String) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "es_PE")
        f.currencySymbol = symbol
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        return f
    }

    /// Formatea siempre desde céntimos, así nunca sale "-0.00" ni "nan".
    static func format(_ value: Double, currency: String = "PEN") -> String {
        let f = currency == "USD" ? usdFormatter : penFormatter
        let safe = self.value(cents(value))
        return f.string(from: NSNumber(value: safe)) ?? "—"
    }

    /// Sin decimales, para gráficos y etiquetas compactas.
    static func formatCompact(_ value: Double, currency: String = "PEN") -> String {
        let symbol = currency == "USD" ? "$" : "S/"
        let units = Int((Double(cents(value)) / 100.0).rounded())
        return symbol + " " + String(units)
    }

    /// Porcentaje para pantalla. `nil` (divisor cero) se muestra como "—",
    /// nunca como "nan%". Ver ACCOUNTING.md §13.
    static func formatPercent(_ part: Double, of total: Double, decimals: Int = 0) -> String {
        guard let p = percent(part, of: total) else { return "—" }
        return String(format: "%.\(decimals)f%%", p)
    }

    static func symbol(for currency: String) -> String {
        currency == "USD" ? "$" : "S/"
    }
}

/// Bolsa multimoneda. Acumula céntimos **por moneda**, para poder mostrar el
/// monto nominal de cada una y avisar cuando un total es una conversión.
///
/// **No** se usa para calcular los totales del periodo: ahí cada movimiento se
/// convierte a soles una sola vez con su propio tipo de cambio
/// (`Accounting.penCents`), que es lo que hace que las sumas sean aditivas.
/// Ver la nota de `Accounting`.
struct MoneyBag {

    private var centsByCurrency: [String: Int] = [:]

    init() {}

    init<T>(_ items: [T], amount: (T) -> Double, currency: (T) -> String) {
        for item in items {
            add(amount(item), currency: currency(item))
        }
    }

    mutating func add(_ amount: Double, currency: String) {
        centsByCurrency[currency, default: 0] += Money.cents(amount)
    }

    mutating func subtract(_ amount: Double, currency: String) {
        centsByCurrency[currency, default: 0] -= Money.cents(amount)
    }

    mutating func merge(_ other: MoneyBag) {
        for (currency, cents) in other.centsByCurrency {
            centsByCurrency[currency, default: 0] += cents
        }
    }

    /// Monto nominal de una sola moneda, sin conversión.
    func amount(in currency: String) -> Double {
        Money.value(centsByCurrency[currency] ?? 0)
    }

    var currencies: [String] { Array(centsByCurrency.keys).sorted() }

    var isEmpty: Bool { centsByCurrency.values.allSatisfy { $0 == 0 } }

    /// Total en soles con un único tipo de cambio. Sólo para bolsas que **no**
    /// se comparan con otras sumas (p. ej. un resumen suelto por moneda).
    func totalInPEN(usdToPen rate: Double) -> Double {
        var total = centsByCurrency["PEN"] ?? 0
        for (currency, cents) in centsByCurrency where currency != "PEN" {
            total += currency == "USD" ? Money.multiplyCents(cents, by: rate) : cents
        }
        return Money.value(total)
    }

    /// `true` si hay más de una moneda: la UI debe avisar que el total es una
    /// conversión, no un monto real.
    var isMixed: Bool { centsByCurrency.filter { $0.value != 0 }.count > 1 }
}
