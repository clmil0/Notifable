import Foundation

struct InterbankParser: BankEmailParser {
    
    var senderEmails: [String] {
        return [] // Add sender emails for Interbank here when known
    }
    
    func parse(cleanText: String) -> Expense? {
        // Implement Interbank parsing logic here
        return nil
    }
}
