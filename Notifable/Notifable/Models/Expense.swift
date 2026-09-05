import Foundation
import SwiftData

@Model
final class Expense {
    var id: UUID
    var amount: Double
    var merchant: String
    var date: Date
    
    // Nuevos campos
    var category: String
    var notes: String?
    var isSubscription: Bool
    var currency: String = "PEN"
    var emailID: String?
    var relatedEmailID: String?
    var isDebt: Bool = false
    var cardLastDigits: String?

    /// Soles por 1 USD el día del movimiento.
    ///
    /// Sin esto, `ExchangeRateService.usdToPenRate` —un valor vivo— se aplicaba a
    /// meses ya cerrados: el total de agosto cambiaba cada vez que se refrescaba
    /// el tipo de cambio, y "vs. mes pasado" comparaba dos tipos distintos.
    /// Ver ACCOUNTING.md §9. `nil` en registros anteriores a la migración; en ese
    /// caso `Accounting` usa el tipo actual como respaldo.
    var fxRateAtCapture: Double?
    
    /// `.nullify`, no `.cascade`: en cascada, "Volver a leer el correo desde
    /// cero" —que borra los gastos para rearmarlos— se llevaba por delante los
    /// cobros que el usuario había registrado a mano, y ésos no están en
    /// ningún correo. Al anular, el cobro sobrevive y `IncomeLinkStore` lo
    /// vuelve a atar cuando el gasto reaparece.
    @Relationship(deleteRule: .nullify, inverse: \Income.debtReference) var payments: [Income]?

    /// - Warning: mezcla monedas (resta un abono de $ 40 como 40 soles) y además
    ///   no es "lo gastado" sino "lo que aún debes", dos cifras que las vistas
    ///   confundían entre sí. Usar `Accounting.outstanding(of:)` para el saldo y
    ///   `amount` para el gasto. Ver ACCOUNTING.md §2 y §5.
    @available(*, deprecated, message: "Mezcla monedas. Usa Accounting.outstanding(of:) para el saldo y amount para el gasto.")
    var unpaidAmount: Double {
        let paid = (payments ?? []).reduce(0) { $0 + $1.amount }
        return max(0, amount - paid)
    }
    
    init(amount: Double, merchant: String, date: Date = Date(), category: String = "Otros", notes: String? = nil, isSubscription: Bool = false, currency: String = "PEN", emailID: String? = nil, isDebt: Bool = false, cardLastDigits: String? = nil, fxRateAtCapture: Double? = nil) {
        self.id = UUID()
        // Céntimos enteros vía Decimal: estable también para 1.005.
        self.amount = Money.normalized(amount)
        self.merchant = merchant
        self.date = date
        self.category = category
        self.notes = notes
        self.isSubscription = isSubscription
        self.currency = currency
        self.emailID = emailID
        self.isDebt = isDebt
        self.cardLastDigits = cardLastDigits
        // Se congela el tipo de cambio del día. En soles no hace falta.
        self.fxRateAtCapture = currency == "PEN"
            ? nil
            : (fxRateAtCapture ?? ExchangeRateService.storedRate)
    }
}
