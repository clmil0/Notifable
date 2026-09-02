import Foundation

/// Tipo de movimiento. Ya existe en `AddExpenseView.swift`; se conserva el nombre.
enum TransactionType: String, CaseIterable, Identifiable {
    case gasto = "Gasto"
    case ingreso = "Ingreso"
    var id: String { rawValue }
}

/// Estado del formulario de alta de movimiento, con validación explícita.
///
/// Reemplaza los 11 `@State` sueltos de `AddExpenseView` por un solo valor.
/// El objetivo del rediseño es que el botón **nunca** acepte un toque sin
/// hacer nada: `validation` dice siempre qué falta, y la vista lo muestra.
struct TransactionDraft {

    var type: TransactionType = .gasto

    /// Texto crudo del teclado numérico. Nunca se guarda: se parsea con
    /// `Money.parse(_:)` y se normaliza a céntimos.
    var amountText: String = ""
    var currency: String = "PEN"
    var date: Date = Date()

    // Gasto
    var merchant: String = ""
    var category: String = "Otros"
    var isSubscription: Bool = false

    // Ingreso
    var source: String = "Transferencia"
    var title: String = ""
    var notes: String = ""
    var isDebtPayment: Bool = false
    var selectedDebt: Expense? = nil

    // MARK: - Monto

    var amount: Double { Money.parse(amountText) ?? 0 }

    var hasAmount: Bool { Money.cents(amount) > 0 }

    /// Saldo de la deuda elegida, en su propia moneda.
    var debtOutstanding: Double? {
        selectedDebt.map { Accounting.outstanding(of: $0) }
    }

    /// Cuánto se pasa el abono del saldo. `nil` si no aplica.
    var excessOverDebt: Double? {
        guard isDebtPayment, let debt = selectedDebt, let saldo = debtOutstanding else { return nil }
        guard debt.currency == currency else { return nil }
        let excess = Money.subtract(amount, saldo)
        return Money.cents(excess) > 0 ? excess : nil
    }

    /// Saldo que quedaría tras el abono.
    var debtRemainder: Double? {
        guard let saldo = debtOutstanding else { return nil }
        return Money.clampedToZero(Money.subtract(saldo, amount))
    }

    /// El abono cancela la deuda. **Se deduce, no se pregunta:** el toggle
    /// "Es el último pago" del diseño anterior permitía cancelar una deuda con
    /// un abono parcial, dejando saldo pendiente en una deuda ya cerrada.
    var cancelsDebt: Bool {
        guard isDebtPayment, let remainder = debtRemainder else { return false }
        return Money.isZero(remainder)
    }

    // MARK: - Validación

    enum Validation: Equatable {
        case ready
        /// Texto exacto que va en el botón deshabilitado.
        case blocked(String)
        /// Error que se muestra bajo el monto, en rojo.
        case invalid(String)

        var isReady: Bool { self == .ready }
    }

    var validation: Validation {
        if amountText.isEmpty || Money.cents(amount) == 0 {
            return .blocked("Escribe un monto")
        }
        if Money.cents(amount) < 0 {
            return .invalid("El monto debe ser positivo")
        }
        // Techo de cordura: un dedo resbalado no debe crear un gasto de millones.
        if Money.cents(amount) > 100_000_000 {
            return .invalid("Monto demasiado alto. Revisa las cifras.")
        }
        if type == .gasto && merchant.trimmed.isEmpty {
            return .blocked("Falta el nombre del comercio")
        }
        if type == .ingreso, isDebtPayment {
            guard let debt = selectedDebt else {
                return .blocked("Elige la deuda a abonar")
            }
            guard debt.currency == currency else {
                return .invalid("La deuda está en \(debt.currency). Cambia la moneda del abono.")
            }
            if let excess = excessOverDebt {
                return .invalid("Supera el saldo de la deuda en " + Money.format(excess, currency: currency))
            }
        }
        if date > Date().addingTimeInterval(60 * 60 * 24) {
            return .invalid("La fecha está en el futuro")
        }
        return .ready
    }

    /// Etiqueta del botón principal cuando está habilitado.
    var actionTitle: String {
        let formatted = Money.format(amount, currency: currency)
        switch (type, isDebtPayment, cancelsDebt) {
        case (.gasto, _, _):        return "Añadir gasto de " + formatted
        case (.ingreso, true, true): return "Abonar " + formatted + " y cancelar deuda"
        case (.ingreso, true, false): return "Abonar " + formatted
        case (.ingreso, false, _):  return "Añadir ingreso de " + formatted
        }
    }

    // MARK: - Teclado numérico

    /// Aplica una tecla al texto del monto. Impide dos separadores decimales
    /// y más de dos decimales — el `TextField` con `.decimalPad` anterior
    /// aceptaba "1.2.3", que `Double(_:)` convertía en `nil` y el `guard`
    /// descartaba en silencio.
    mutating func press(_ key: KeypadKey) {
        switch key {
        case .digit(let d):
            if let dot = amountText.firstIndex(of: ".") {
                let decimals = amountText.distance(from: dot, to: amountText.endIndex) - 1
                guard decimals < 2 else { return }
            }
            guard amountText.replacingOccurrences(of: ".", with: "").count < 9 else { return }
            if amountText == "0" { amountText = String(d) } else { amountText.append(String(d)) }
        case .decimal:
            guard !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        case .backspace:
            guard !amountText.isEmpty else { return }
            amountText.removeLast()
        }
    }

    enum KeypadKey: Hashable {
        case digit(Int)
        case decimal
        case backspace
    }

    /// Monto mostrado en el hero. Vacío muestra "0.00" en color terciario.
    var displayAmount: String {
        guard !amountText.isEmpty else { return "0.00" }
        return amountText
    }

    // MARK: - Persistencia

    /// Crea el `Expense`. Sólo llamar con `validation == .ready`.
    func makeExpense() -> Expense? {
        guard validation.isReady, type == .gasto else { return nil }
        // El orden de los parámetros es el del `init` del modelo.
        return Expense(
            amount: Money.normalized(amount),
            merchant: merchant.trimmed,
            date: date,
            category: category,
            isSubscription: isSubscription,
            currency: currency
        )
    }

    /// Crea el `Income`. El monto se limita al saldo por si la validación se
    /// salta desde otro punto de entrada (doble red).
    func makeIncome() -> Income? {
        guard validation.isReady, type == .ingreso else { return nil }
        let debt = isDebtPayment ? selectedDebt : nil
        let finalAmount = debt.map { Accounting.clampPayment(amount, to: $0) } ?? Money.normalized(amount)
        guard Money.cents(finalAmount) > 0 else { return nil }
        return Income(
            amount: finalAmount,
            currency: currency,
            source: source,
            title: title.trimmed.isEmpty ? nil : title.trimmed,
            date: date,
            notes: notes.trimmed.isEmpty ? nil : notes.trimmed,
            debtReference: debt,
            isFinalDebtPayment: cancelsDebt
        )
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Money {

    /// Parsea texto escrito por una persona. Acepta coma o punto como decimal,
    /// separadores de miles, espacios y símbolos de moneda.
    ///
    /// `Double(amountText.replacingOccurrences(of: ",", with: "."))` fallaba con
    /// "1.234,56" (formato local) y con "1 200".
    static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        for token in ["S/", "US$", "$", "PEN", "USD", " ", "\u{00A0}"] {
            s = s.replacingOccurrences(of: token, with: "")
        }
        let lastComma = s.lastIndex(of: ",")
        let lastDot = s.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (c?, d?):
            // El separador más a la derecha es el decimal; el otro es de miles.
            if c > d {
                s = s.replacingOccurrences(of: ".", with: "")
                s = s.replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
        case (.some, .none):
            s = s.replacingOccurrences(of: ",", with: ".")
        case (.none, .some(let d)):
            // Punto usado como separador de miles: "1.200" sin decimales.
            let decimals = s.distance(from: d, to: s.endIndex) - 1
            if decimals == 3 && s.filter({ $0 == "." }).count == 1 && s.count > 4 {
                s = s.replacingOccurrences(of: ".", with: "")
            }
        case (.none, .none):
            break
        }
        guard let value = Double(s), value.isFinite else { return nil }
        return normalized(value)
    }
}
