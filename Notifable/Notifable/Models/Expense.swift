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
    var isDebt: Bool = false
    var cardLastDigits: String?
    
    @Relationship(deleteRule: .cascade, inverse: \Income.debtReference) var payments: [Income]?
    
    var unpaidAmount: Double {
        let paid = (payments ?? []).reduce(0) { $0 + $1.amount }
        return max(0, amount - paid)
    }
    
    init(amount: Double, merchant: String, date: Date = Date(), category: String = "Otros", notes: String? = nil, isSubscription: Bool = false, currency: String = "PEN", emailID: String? = nil, isDebt: Bool = false, cardLastDigits: String? = nil) {
        self.id = UUID()
        // Aseguramos que el valor guardado en la base de datos tenga máximo 2 decimales
        self.amount = (amount * 100).rounded() / 100
        self.merchant = merchant
        self.date = date
        self.category = category
        self.notes = notes
        self.isSubscription = isSubscription
        self.currency = currency
        self.emailID = emailID
        self.isDebt = isDebt
        self.cardLastDigits = cardLastDigits
    }
}
