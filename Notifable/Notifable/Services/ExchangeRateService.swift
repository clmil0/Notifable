import Foundation
import Combine

class ExchangeRateService: ObservableObject {
    static let shared = ExchangeRateService()
    
    @Published var usdToPenRate: Double = UserDefaults.standard.double(forKey: "usdToPenRate")
    
    init() {
        if usdToPenRate == 0 {
            usdToPenRate = 3.75 // Default fallback
        }
        fetchLatestRate()
    }
    
    func fetchLatestRate() {
        guard let url = URL(string: "https://api.exchangerate-api.com/v4/latest/USD") else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                print("Failed to fetch exchange rate: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let rates = json["rates"] as? [String: Any],
                   let penRate = rates["PEN"] as? Double {
                    
                    DispatchQueue.main.async {
                        self?.usdToPenRate = penRate
                        UserDefaults.standard.set(penRate, forKey: "usdToPenRate")
                    }
                }
            } catch {
                print("Failed to decode exchange rate: \(error.localizedDescription)")
            }
        }.resume()
    }
}
