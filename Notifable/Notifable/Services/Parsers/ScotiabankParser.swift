import Foundation

struct ScotiabankParser: BankEmailParser {
    
    var senderEmails: [String] {
        return [] // Add sender emails for Scotiabank here when known
    }
    
    func parse(cleanText: String) -> Expense? {
        // Implement Scotiabank parsing logic here
        return nil
    }
}
