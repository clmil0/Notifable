import Foundation

struct YapeParser: BankEmailParser {
    
    var senderEmails: [String] {
        return [] // Add sender emails for Yape here when known
    }
    
    func parse(cleanText: String) -> Expense? {
        // Implement Yape parsing logic here
        return nil
    }
}
