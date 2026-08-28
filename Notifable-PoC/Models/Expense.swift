import Foundation
import SwiftData

@Model
final class Expense {
    var id: UUID
    var amount: Double
    var merchant: String
    var date: Date
    
    init(amount: Double, merchant: String, date: Date = Date()) {
        self.id = UUID()
        self.amount = amount
        self.merchant = merchant
        self.date = date
    }
}
