import Foundation
import SwiftData

class GmailSyncService: ObservableObject {
    
    static let shared = GmailSyncService()
    
    @Published var isSyncing: Bool = false
    @Published var lastSyncError: String?
    
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    
    // Lista de parsers modulares de cada banco
    private let parsers: [BankEmailParser] = [
        BBVAParser(),
        BCPParser(),
        YapeParser(),
        InterbankParser(),
        ScotiabankParser()
    ]
    
    // Configura el ModelContext desde el lugar donde se llame
    var modelContext: ModelContext?
    
    func syncEmails() {
        DispatchQueue.main.async {
            self.isSyncing = true
            self.lastSyncError = nil
        }
        
        guard let token = GmailAuthService.shared.getAccessToken() else {
            DispatchQueue.main.async {
                self.isSyncing = false
                self.lastSyncError = "No access token"
            }
            return
        }
        
        fetchMessageList(token: token) { [weak self] result in
            switch result {
            case .success(let messages):
                self?.processMessages(messages, token: token)
            case .failure(let error):
                // Token might be expired, try to refresh
                print("Failed to fetch messages: \(error). Trying to refresh token...")
                GmailAuthService.shared.refreshAccessToken { newToken in
                    if let newToken = newToken {
                        self?.fetchMessageList(token: newToken) { result in
                            switch result {
                            case .success(let msgs):
                                self?.processMessages(msgs, token: newToken)
                            case .failure(let err):
                                DispatchQueue.main.async {
                                    self?.isSyncing = false
                                    self?.lastSyncError = err.localizedDescription
                                }
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.isSyncing = false
                            self?.lastSyncError = "Token refresh failed"
                        }
                    }
                }
            }
        }
    }
    
    private func fetchMessageList(token: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        // Buscar correos dinámicamente según los bancos soportados
        let allEmails = parsers.flatMap { $0.senderEmails }
        let query = allEmails.isEmpty ? "" : allEmails.map { "from:\($0)" }.joined(separator: " OR ")
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        
        let urlString = "\(baseURL)/messages?q=\(encodedQuery)&maxResults=100"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                completion(.failure(NSError(domain: "Auth", code: 401, userInfo: nil)))
                return
            }
            guard let data = data else { return }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let messages = json["messages"] as? [[String: Any]] {
                    completion(.success(messages))
                } else {
                    completion(.success([]))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func processMessages(_ messages: [[String: Any]], token: String) {
        let processedIDs = UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []
        var newIDs = processedIDs
        let queue = DispatchQueue(label: "com.notifable.syncQueue") // Para evitar race conditions
        
        let group = DispatchGroup()
        var newExpensesFound = 0
        
        for message in messages {
            guard let id = message["id"] as? String else { continue }
            if processedIDs.contains(id) { continue } // Skip already processed
            
            group.enter()
            fetchMessageDetails(id: id, token: token) { [weak self] body in
                if let body = body, let expense = self?.parseEmailBody(body) {
                    DispatchQueue.main.async {
                        if let context = self?.modelContext {
                            context.insert(expense)
                            try? context.save()
                            newExpensesFound += 1
                        }
                    }
                }
                
                queue.async {
                    newIDs.append(id)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            queue.sync {
                UserDefaults.standard.set(newIDs, forKey: "processedEmailIDs")
            }
            self.isSyncing = false
            print("Sync complete. Found \(newExpensesFound) new expenses.")
        }
    }
    
    func resetSyncState() {
        UserDefaults.standard.removeObject(forKey: "processedEmailIDs")
    }
    
    private func fetchMessageDetails(id: String, token: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/messages/\(id)?format=full") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    let bodyText = self.extractFullText(from: json)
                    completion(bodyText)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    private func extractFullText(from json: [String: Any]) -> String {
        guard let payload = json["payload"] as? [String: Any] else {
            return json["snippet"] as? String ?? ""
        }
        
        var plainText = ""
        var htmlText = ""
        
        func traverseParts(_ parts: [[String: Any]]) {
            for part in parts {
                if let mimeType = part["mimeType"] as? String {
                    if mimeType == "text/plain", let body = part["body"] as? [String: Any], let data = body["data"] as? String, let decoded = self.decodeBase64Url(data) {
                        plainText += decoded + " "
                    } else if mimeType == "text/html", let body = part["body"] as? [String: Any], let data = body["data"] as? String, let decoded = self.decodeBase64Url(data) {
                        htmlText += decoded + " "
                    }
                }
                if let subParts = part["parts"] as? [[String: Any]] {
                    traverseParts(subParts)
                }
            }
        }
        
        if let parts = payload["parts"] as? [[String: Any]] {
            traverseParts(parts)
        } else if let mimeType = payload["mimeType"] as? String, let body = payload["body"] as? [String: Any], let data = body["data"] as? String, let decoded = self.decodeBase64Url(data) {
            if mimeType == "text/plain" { plainText = decoded }
            if mimeType == "text/html" { htmlText = decoded }
        }
        
        if !plainText.isEmpty {
            return plainText
        } else if !htmlText.isEmpty {
            // Strip HTML tags roughly by replacing them with spaces
            var stripped = htmlText.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression, range: nil)
            stripped = stripped.replacingOccurrences(of: "&nbsp;", with: " ")
            stripped = stripped.replacingOccurrences(of: "&aacute;", with: "á")
            stripped = stripped.replacingOccurrences(of: "&eacute;", with: "é")
            stripped = stripped.replacingOccurrences(of: "&iacute;", with: "í")
            stripped = stripped.replacingOccurrences(of: "&oacute;", with: "ó")
            stripped = stripped.replacingOccurrences(of: "&uacute;", with: "ú")
            stripped = stripped.replacingOccurrences(of: "&ntilde;", with: "ñ")
            stripped = stripped.replacingOccurrences(of: "&bull;", with: "")
            return stripped
        }
        
        return json["snippet"] as? String ?? ""
    }
    
    private func parseEmailBody(_ text: String) -> Expense? {
        let cleanText = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        
        for parser in parsers {
            if let expense = parser.parse(cleanText: cleanText) {
                return applyAutoCategorization(to: expense)
            }
        }
        
        return nil
    }
    
    // MARK: - Autocategorización Global
    
    private func applyAutoCategorization(to expense: Expense) -> Expense {
        var autoCategory = "Sin Clasificar"
        let lowerMerchant = expense.merchant.lowercased()
        if lowerMerchant.contains("starbucks") || lowerMerchant.contains("eats") || lowerMerchant.contains("tambo") || lowerMerchant.contains("sharethemeal") {
            autoCategory = "Comida"
        } else if lowerMerchant.contains("uber") || lowerMerchant.contains("lyft") || lowerMerchant.contains("didi") || lowerMerchant.contains("cabify") || lowerMerchant.contains("yango") {
            autoCategory = "Transporte"
        } else if lowerMerchant.contains("netflix") || lowerMerchant.contains("spotify") || lowerMerchant.contains("apple") || lowerMerchant.contains("disney") || lowerMerchant.contains("prime") {
            autoCategory = "Entretenimiento"
        }
        
        let isSub = autoCategory == "Entretenimiento"
        
        expense.category = autoCategory
        expense.isSubscription = isSub
        return expense
    }
    
    private func decodeBase64Url(_ base64Url: String) -> String? {
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let length = Double(base64.lengthOfBytes(using: String.Encoding.utf8))
        let requiredLength = 4 * ceil(length / 4.0)
        let paddingLength = requiredLength - length
        if paddingLength > 0 {
            let padding = "".padding(toLength: Int(paddingLength), withPad: "=", startingAt: 0)
            base64 += padding
        }
        
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
