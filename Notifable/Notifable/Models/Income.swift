import Foundation
import SwiftData

@Model
final class Income {
    var id: UUID
    var amount: Double
    var currency: String
    var source: String // Ej: "Plin", "Yape", "Efectivo", "Transferencia"
    var title: String? // Título opcional, ej: "Sueldo", "Venta de laptop"
    var date: Date
    var notes: String?

    /// Soles por 1 USD el día del movimiento. Ver ACCOUNTING.md §9.
    var fxRateAtCapture: Double?
    
    // Relación a Deuda (Opcional)
    var debtReference: Expense?
    var isFinalDebtPayment: Bool? = false

    /// `true` si este movimiento es un abono a una deuda: liquida un pasivo, no
    /// es ingreso. `Accounting` lo excluye de `income` y lo reporta en
    /// `debtPayments`. Ver ACCOUNTING.md §3 y §4.
    var isDebtPayment: Bool { debtReference != nil }
    
    init(amount: Double, currency: String = "PEN", source: String, title: String? = nil, date: Date = Date(), notes: String? = nil, debtReference: Expense? = nil, isFinalDebtPayment: Bool? = false, fxRateAtCapture: Double? = nil) {
        self.id = UUID()
        self.amount = Money.normalized(amount)
        self.currency = currency
        self.source = source
        self.title = title
        self.date = date
        self.notes = notes
        self.debtReference = debtReference
        self.isFinalDebtPayment = isFinalDebtPayment
        self.fxRateAtCapture = currency == "PEN"
            ? nil
            : (fxRateAtCapture ?? ExchangeRateService.storedRate)
    }
}
