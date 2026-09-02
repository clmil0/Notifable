import SwiftUI

/// Icono y color de cada categoría, en un solo sitio.
///
/// Antes cada pantalla tenía su propia copia de este `switch` —Resumen,
/// Categorías, el detalle— y ya habían empezado a divergir: Supermercado era
/// teal en la dona y verde en las filas.
enum CategoryStyle {

    static func icon(for category: String) -> String {
        switch category {
        case "Comida": return "fork.knife"
        case "Transporte": return "car.fill"
        case "Entretenimiento": return "play.tv.fill"
        case "Supermercado": return "cart.fill"
        case "Servicios": return "bolt.fill"
        case "Salud": return "cross.case.fill"
        case "Compras": return "bag.fill"
        case Accounting.unclassified: return "tray.full.fill"
        default: return "bag.fill"
        }
    }

    static func color(for category: String, accent: Color) -> Color {
        switch category {
        case "Comida": return .orange
        case "Transporte": return .blue
        case "Entretenimiento": return accent
        case "Supermercado": return .teal
        case "Otros": return .green
        case "Servicios": return .yellow
        case "Salud": return .pink
        case "Compras": return .indigo
        case Accounting.unclassified: return .gray
        default:
            // Color estable derivado del nombre, para categorías creadas por el
            // usuario. `hashValue` cambia entre ejecuciones, así que no sirve.
            let sum = category.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return Color(hue: Double(sum % 360) / 360.0, saturation: 0.6, brightness: 0.8)
        }
    }

    /// Las categorías por defecto, sin "Sin Clasificar": ése es el estado de lo
    /// que llega del banco sin regla, no algo que se elija a mano.
    static let defaults = ["Comida", "Transporte", "Entretenimiento", "Supermercado", "Otros"]

    /// Todas las categorías elegibles, con las más usadas por delante.
    static func selectable(history: [Expense]) -> [String] {
        var counts: [String: Int] = [:]
        for expense in history where expense.category != Accounting.unclassified {
            counts[expense.category, default: 0] += 1
        }
        let known = Set(counts.keys).union(defaults)
        return known.sorted { lhs, rhs in
            let l = counts[lhs] ?? 0
            let r = counts[rhs] ?? 0
            return l == r ? lhs < rhs : l > r
        }
    }
}
