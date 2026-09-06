import Foundation

/// Puente entre los modelos de SwiftData y la contabilidad pura.
///
/// `Accounting` trabaja sobre `ExpenseSnapshot` / `IncomeSnapshot` para poder
/// probarse sin base de datos. Aquí se traducen los `@Model` una sola vez, en el
/// mismo sitio, de modo que ninguna vista vuelva a interpretar `payments` ni a
/// decidir por su cuenta qué es un ingreso.
extension Expense {

    /// Abonos que sí cuentan: los de la misma moneda del gasto.
    var paymentsInOwnCurrency: Double {
        Money.sum((payments ?? []).filter { $0.currency == currency }) { $0.amount }
    }

    var hasForeignPayments: Bool {
        (payments ?? []).contains { $0.currency != currency }
    }

    var accountingSnapshot: ExpenseSnapshot {
        ExpenseSnapshot(
            amount: amount,
            currency: currency,
            date: date,
            category: category,
            merchant: merchant,
            isDebt: isDebt,
            fxRateAtCapture: fxRateAtCapture,
            paymentsInOwnCurrency: paymentsInOwnCurrency,
            hasForeignPayments: hasForeignPayments
        )
    }

    /// El mismo snapshot, pero **sin tocar `payments`** cuando el gasto no es
    /// deuda. Sólo para el camino masivo (`Accounting.totals`).
    ///
    /// `payments` es una relación de SwiftData: leerla resuelve un *fault* por
    /// cada gasto, y `accountingSnapshot` la leía siempre. `totals` únicamente
    /// mira los abonos dentro de `if e.isDebt`, así que para todo lo demás
    /// —la inmensa mayoría de los movimientos— ese trabajo se tiraba entero.
    /// Con un año filtrado y varios `totals` por dibujado eran miles de faults
    /// por fotograma.
    ///
    /// No se toca `accountingSnapshot`: ése lo usan `Accounting.outstanding` y
    /// compañía sobre gastos sueltos, donde el saldo tiene que salir bien sea
    /// cual sea la marca de deuda.
    var totalsSnapshot: ExpenseSnapshot {
        guard isDebt else {
            return ExpenseSnapshot(
                amount: amount,
                currency: currency,
                date: date,
                category: category,
                merchant: merchant,
                isDebt: false,
                fxRateAtCapture: fxRateAtCapture
            )
        }
        return accountingSnapshot
    }
}

extension Income {

    var accountingSnapshot: IncomeSnapshot {
        IncomeSnapshot(
            amount: amount,
            currency: currency,
            date: date,
            isDebtPayment: debtReference != nil,
            fxRateAtCapture: fxRateAtCapture
        )
    }
}

extension Accounting {

    static func totals(expenses: [Expense],
                       incomes: [Income],
                       period: Period,
                       usdToPen: Double) -> PeriodTotals {
        totals(expenses: expenses.map(\.totalsSnapshot),
               incomes: incomes.map(\.accountingSnapshot),
               period: period,
               usdToPen: usdToPen)
    }

    /// Saldo pendiente de una deuda, contando sólo abonos de su misma moneda.
    static func outstanding(of expense: Expense) -> Double {
        outstanding(of: expense.accountingSnapshot)
    }

    static func paid(of expense: Expense) -> Double {
        expense.paymentsInOwnCurrency
    }

    static func hasForeignPayments(_ expense: Expense) -> Bool {
        expense.hasForeignPayments
    }

    /// Máximo abono aceptable. La UI debe rechazar el exceso, no absorberlo.
    static func clampPayment(_ amount: Double, to expense: Expense) -> Double {
        clampPayment(amount, to: expense.accountingSnapshot)
    }

    /// Monto de un gasto en soles, con su propio tipo de cambio.
    static func amountInPEN(_ expense: Expense, fallbackRate: Double) -> Double {
        Money.value(penCents(expense.accountingSnapshot, fallbackRate: fallbackRate))
    }

    static func amountInPEN(_ income: Income, fallbackRate: Double) -> Double {
        Money.value(penCents(income.accountingSnapshot, fallbackRate: fallbackRate))
    }
}
