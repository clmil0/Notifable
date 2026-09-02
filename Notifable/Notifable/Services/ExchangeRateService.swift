import Foundation
import Combine

class ExchangeRateService: ObservableObject {
    static let shared = ExchangeRateService()

    static let rateKey = "usdToPenRate"
    static let rateDateKey = "usdToPenRateDate"
    static let fallbackRate: Double = 3.75

    /// Último tipo de cambio conocido, leído de `UserDefaults` sin instanciar el
    /// servicio ni disparar red. Lo usan los `init` de los modelos para congelar
    /// `fxRateAtCapture` (ACCOUNTING.md §9) desde cualquier proceso: la app, un
    /// App Intent o un parser de correo.
    static var storedRate: Double {
        let stored = UserDefaults.standard.double(forKey: rateKey)
        return stored > 0 ? stored : fallbackRate
    }

    /// Cuándo se obtuvo ese tipo de cambio. Permite avisar "tipo de cambio de
    /// hace 3 días" cuando la red falla, en lugar de presentarlo como actual.
    static var storedRateDate: Date? {
        let t = UserDefaults.standard.double(forKey: rateDateKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Días de antigüedad del tipo de cambio, o `nil` si nunca se obtuvo.
    static var rateAgeInDays: Int? {
        guard let date = storedRateDate else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }

    /// `true` si el tipo de cambio lleva más de un día sin refrescarse.
    static var isRateStale: Bool { (rateAgeInDays ?? Int.max) > 1 }

    @Published var usdToPenRate: Double = ExchangeRateService.storedRate
    @Published var rateDate: Date? = ExchangeRateService.storedRateDate

    init() {
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
                   let penRate = rates["PEN"] as? Double,
                   penRate > 0 {
                    
                    let now = Date()
                    DispatchQueue.main.async {
                        self?.usdToPenRate = penRate
                        self?.rateDate = now
                        UserDefaults.standard.set(penRate, forKey: ExchangeRateService.rateKey)
                        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: ExchangeRateService.rateDateKey)
                    }
                }
            } catch {
                print("Failed to decode exchange rate: \(error.localizedDescription)")
            }
        }.resume()
    }
}
