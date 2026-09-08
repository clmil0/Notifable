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

    /// - Note: aquí hubo un `totalsSnapshot` que se saltaba la relación
    ///   `payments` cuando el gasto no era deuda, para ahorrarse un *fault* de
    ///   SwiftData por movimiento. Dejó de ser válido al pasar `spent` a contar
    ///   el **gasto neto**: ahora cualquier gasto con devoluciones aporta menos,
    ///   y uno ya saldado (que deja de tener `isDebt`) se habría contado entero.
    ///   Correcto antes que rápido; el ahorro grande —calcular los totales una
    ///   sola vez por dibujado en vez de ocho— sigue en pie.
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
        totals(expenses: expenses.map(\.accountingSnapshot),
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
