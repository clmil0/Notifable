import Testing
import Foundation
@testable import Notifable

/// La lista de verificación de ADD_TRANSACTION.md.
///
/// Lo que se comprueba, sobre todo, es que el botón nunca acepte un toque sin
/// hacer nada: el modal anterior tenía un `guard` que devolvía en silencio.
struct TransactionDraftTests {

    // MARK: - 1 y 2. Monto

    @Test("1. Escribir '1.2.3' es imposible: el segundo punto se ignora")
    func dosPuntosDecimales() {
        var draft = TransactionDraft()
        draft.press(.digit(1))
        draft.press(.decimal)
        draft.press(.digit(2))
        draft.press(.decimal)
        draft.press(.digit(3))
        #expect(draft.amountText == "1.23")
        #expect(Money.equals(draft.amount, 1.23))
    }

    @Test("El teclado corta a dos decimales y a nueve dígitos")
    func topesDelTeclado() {
        var draft = TransactionDraft()
        for digit in [1, 2] { draft.press(.digit(digit)) }
        draft.press(.decimal)
        for digit in [3, 4, 5] { draft.press(.digit(digit)) }
        #expect(draft.amountText == "12.34", "salió \(draft.amountText)")

        var long = TransactionDraft()
        for _ in 0..<15 { long.press(.digit(9)) }
        #expect(long.amountText.count == 9)
    }

    @Test("2. '1.234,56' y '1 200' se leen bien")
    func parseoTolerante() {
        // Double("1.234,56") es nil, y el ?? 0.0 del modal anterior lo volvía cero.
        #expect(Money.equals(Money.parse("1.234,56") ?? 0, 1234.56))
        #expect(Money.equals(Money.parse("1 200") ?? 0, 1200))
        #expect(Money.equals(Money.parse("1,234.56") ?? 0, 1234.56))
        #expect(Money.equals(Money.parse("S/ 86.40") ?? 0, 86.40))
        #expect(Money.equals(Money.parse("45,50") ?? 0, 45.50))
        #expect(Money.parse("") == nil)
        #expect(Money.parse("abc") == nil)
    }

    @Test("9. El monto guardado coincide en céntimos con lo escrito")
    func centimosExactos() {
        var draft = TransactionDraft(type: .gasto)
        draft.merchant = "Metro"
        for key in [TransactionDraft.KeypadKey.digit(8), .digit(6), .decimal, .digit(4), .digit(0)] {
            draft.press(key)
        }
        #expect(draft.amountText == "86.40")
        #expect(Money.cents(draft.amount) == 8640)
        #expect(Money.cents(draft.makeExpense()?.amount ?? 0) == 8640)
    }

    // MARK: - 7. Validación

    @Test("7. Sin monto y sin comercio el botón dice qué falta")
    func validacionExplica() {
        var draft = TransactionDraft(type: .gasto)
        #expect(draft.validation == .blocked("Escribe un monto"))

        draft.amountText = "50"
        #expect(draft.validation == .blocked("Falta el nombre del comercio"))

        draft.merchant = "   "
        #expect(draft.validation == .blocked("Falta el nombre del comercio"),
                "un nombre de sólo espacios no cuenta")

        draft.merchant = "Metro"
        #expect(draft.validation == .ready)
        #expect(draft.actionTitle.contains("Añadir gasto"))
    }

    @Test("Un monto absurdo o una fecha futura se marcan como error")
    func limites() {
        var draft = TransactionDraft(type: .gasto)
        draft.merchant = "Metro"
        draft.amountText = "9999999999"
        if case .invalid = draft.validation {} else {
            Issue.record("un monto de mil millones debería ser .invalid")
        }

        var futuro = TransactionDraft(type: .gasto)
        futuro.merchant = "Metro"
        futuro.amountText = "50"
        futuro.date = Date().addingTimeInterval(60 * 60 * 24 * 3)
        if case .invalid = futuro.validation {} else {
            Issue.record("una fecha en el futuro debería ser .invalid")
        }
    }

    // MARK: - 3, 4, 5 y 6. Abono a deuda

    /// Deuda de 500 con 100 ya abonados: saldo 400.
    private func deudaConSaldo() -> Expense {
        let debt = Expense(amount: 500, merchant: "Rappi", date: Date(),
                           category: "Comida", currency: "PEN", isDebt: true)
        let payment = Income(amount: 100, currency: "PEN", source: "Yape",
                             date: Date(), debtReference: debt)
        debt.payments = [payment]
        return debt
    }

    private func abono(_ amount: String, to debt: Expense, currency: String = "PEN") -> TransactionDraft {
        var draft = TransactionDraft(type: .ingreso)
        draft.amountText = amount
        draft.currency = currency
        draft.source = "Yape"
        draft.isDebtPayment = true
        draft.selectedDebt = debt
        return draft
    }

    @Test("3. Un abono mayor al saldo bloquea el botón y dice cuánto se pasa")
    func abonoExcesivo() {
        let debt = deudaConSaldo()
        let draft = abono("500", to: debt)

        #expect(Money.equals(draft.debtOutstanding ?? 0, 400))
        #expect(Money.equals(draft.excessOverDebt ?? 0, 100))
        if case .invalid(let message) = draft.validation {
            #expect(message.contains("100"), "el mensaje debería decir cuánto se pasa: \(message)")
        } else {
            Issue.record("un abono de 500 sobre un saldo de 400 debería ser .invalid")
        }
    }

    @Test("4. Un abono parcial no cancela la deuda")
    func abonoParcial() {
        let debt = deudaConSaldo()
        let draft = abono("150", to: debt)

        #expect(draft.validation == .ready)
        #expect(!draft.cancelsDebt, "150 sobre un saldo de 400 no cancela nada")
        #expect(Money.equals(draft.debtRemainder ?? 0, 250))
        #expect(draft.makeIncome()?.isFinalDebtPayment == false)
    }

    @Test("5. Un abono que deja el saldo en cero sí cancela, y lo anuncia")
    func abonoQueCancela() {
        let debt = deudaConSaldo()
        let draft = abono("400", to: debt)

        #expect(draft.validation == .ready)
        #expect(draft.cancelsDebt)
        #expect(Money.equals(draft.debtRemainder ?? 0, 0))
        #expect(draft.actionTitle.contains("cancelar deuda"))
        #expect(draft.makeIncome()?.isFinalDebtPayment == true)
    }

    @Test("6. Un abono en otra moneda bloquea el botón con explicación")
    func abonoEnOtraMoneda() {
        let debt = deudaConSaldo()                       // en PEN
        let draft = abono("100", to: debt, currency: "USD")

        if case .invalid(let message) = draft.validation {
            #expect(message.contains("PEN"), "debería nombrar la moneda de la deuda: \(message)")
        } else {
            Issue.record("un abono en USD sobre una deuda en PEN debería ser .invalid")
        }
    }

    @Test("Sin deuda elegida, el abono pide elegirla")
    func abonoSinDeuda() {
        var draft = TransactionDraft(type: .ingreso)
        draft.amountText = "100"
        draft.isDebtPayment = true
        #expect(draft.validation == .blocked("Elige la deuda a abonar"))
    }

    @Test("El ingreso normal no toca ninguna deuda")
    func ingresoNormal() {
        var draft = TransactionDraft(type: .ingreso)
        draft.amountText = "2500"
        draft.source = "Transferencia"
        draft.title = "  Sueldo  "

        #expect(draft.validation == .ready)
        let income = draft.makeIncome()
        #expect(income?.debtReference == nil)
        #expect(income?.title == "Sueldo", "el título se recorta")
        #expect(income?.isFinalDebtPayment == false)
    }

    // MARK: - 8. Fecha

    @Test("8. Un gasto de ayer se guarda con la fecha de ayer")
    func gastoConFecha() {
        let ayer = Period.calendar.date(byAdding: .day, value: -1, to: Date())!
        var draft = TransactionDraft(type: .gasto)
        draft.amountText = "32.50"
        draft.merchant = "Metro"
        draft.category = "Comida"
        draft.date = ayer

        let expense = draft.makeExpense()
        #expect(expense != nil)
        #expect(Period.calendar.isDate(expense?.date ?? Date(), inSameDayAs: ayer),
                "el gasto no tenía campo de fecha y siempre se guardaba con Date()")
        #expect(expense?.category == "Comida")
    }

    // MARK: - Cambio de tipo

    @Test("makeExpense y makeIncome sólo producen su propio tipo")
    func tiposCruzados() {
        var gasto = TransactionDraft(type: .gasto)
        gasto.amountText = "10"
        gasto.merchant = "Metro"
        #expect(gasto.makeIncome() == nil)

        var ingreso = TransactionDraft(type: .ingreso)
        ingreso.amountText = "10"
        #expect(ingreso.makeExpense() == nil)
    }
}
