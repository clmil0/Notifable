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

    /// El id del correo que lo generó (una constancia de Yapeo recibido, por
    /// ejemplo). `nil` = anotado a mano. Igual que `Expense.emailID`: permite
    /// deduplicar en cada sincronización y evita respaldarlo en
    /// `ConfigBackupManager` — se rearma solo releyendo el correo.
    var emailID: String?

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

extension Income {
    /// Borra el ingreso y su vínculo guardado. Si era el abono que cerraba una
    /// deuda, la deuda vuelve a quedar por cobrar.
    func deleteRestoringDebt(in modelContext: ModelContext) {
        IncomeLinkStore.remove(incomeID: id)
        if let debt = debtReference, isFinalDebtPayment == true, !debt.isDebt {
            debt.isDebt = true
            ExpenseEditStore.record(debt, isDebt: true)
            let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.isDebt == true })
            let hasDebts = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
            NotificationManager.shared.updateDebtNotification(hasDebts: hasDebts)
        }
        modelContext.delete(self)
        try? modelContext.save()
    }
}
