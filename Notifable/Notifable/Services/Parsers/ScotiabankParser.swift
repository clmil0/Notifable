import Foundation

struct ScotiabankParser: BankEmailParser {
    
    var bankName: String {
        return "Scotiabank"
    }
    
    var senderEmails: [String] {
        return [] // Add sender emails for Scotiabank here when known
    }
    
    func parse(cleanText: String) -> Expense? {
        // Implement Scotiabank parsing logic here
        return nil
    }
}
