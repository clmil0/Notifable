import Foundation

/// Enlaces `agrupay://` que abren la app en un sitio concreto.
///
/// Los usan los widgets (que no pueden escribir en la base: ver
/// `WidgetSnapshot`) y cualquier atajo de la app Atajos. Un solo tipo para
/// construirlos y leerlos, así el widget y la app no pueden desalinearse.
enum AppDeepLink: Equatable {

    static let scheme = "agrupay"

    /// Abre el formulario. `source` sólo aplica a ingresos ("Yape", "Plin"…).
    case add(isIncome: Bool, source: String?)
    /// Registra un gasto rápido al momento, con la opción de deshacer.
    case quick(UUID)
    case summary
    case categories
    case pending
    case rhythm

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case let .add(isIncome, source):
            c.host = "add"
            var items = [URLQueryItem(name: "type", value: isIncome ? "ingreso" : "gasto")]
            if let source { items.append(URLQueryItem(name: "source", value: source)) }
            c.queryItems = items
        case .quick(let id):
            c.host = "quick"
            c.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        case .summary:    c.host = "summary"
        case .categories: c.host = "categories"
        case .pending:    c.host = "pending"
        case .rhythm:     c.host = "rhythm"
        }
        return c.url ?? URL(string: "\(Self.scheme)://summary")!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                               uniquingKeysWith: { first, _ in first })

        switch url.host?.lowercased() {
        case "add":
            let source = query["source"].flatMap { $0.isEmpty ? nil : $0 }
            self = .add(isIncome: query["type"] == "ingreso", source: source)
        case "quick":
            guard let id = query["id"].flatMap(UUID.init(uuidString:)) else { return nil }
            self = .quick(id)
        case "summary":    self = .summary
        case "categories": self = .categories
        case "pending":    self = .pending
        case "rhythm":     self = .rhythm
        default: return nil
        }
    }
}
