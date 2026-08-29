import Foundation

struct BCPParser: BankEmailParser {
    
    var bankName: String {
        return "BCP"
    }
    
    var senderEmails: [String] {
        return [] // Add sender emails for BCP here when known
    }
    
    func parse(cleanText: String) -> Expense? {
        // Implement BCP parsing logic here
        return nil
    }
}
