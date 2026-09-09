import SwiftUI

enum AppThemeColor: String, CaseIterable, Identifiable {
    case purple = "Morado"
    case blue = "Azul"
    case green = "Verde"
    case orange = "Naranja"
    case red = "Rojo"
    // Temas pastel de dos colores: un segundo acento con roles fijos
    // (ingresos, hoy en el scrubber, badge de Pendientes, suscripciones,
    // deltas a la baja) — ver `secondaryColor` y compañía más abajo.
    case lavender = "Lavanda"
    case peach = "Durazno"
    case sky = "Cielo"
    case rose = "Rosa"

    var id: String { self.rawValue }

    /// `true` para los temas pastel de dos colores, que tienen un
    /// `secondaryColor` propio en vez de heredar el mismo acento.
    var isDuotone: Bool {
        switch self {
        case .lavender, .peach, .sky, .rose: return true
        case .purple, .blue, .green, .orange, .red: return false
        }
    }

    var color: Color {
        switch self {
        case .purple: return .purple
        // El azul de marca del ícono (#2E5BFF) — no el azul de sistema — para
        // que "Azul" en Ajustes sea el mismo color que ve el usuario en el
        // ícono y el splash.
        case .blue: return AppBrand.accent
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .lavender: return Color(red: 0.659, green: 0.600, blue: 0.941)   // #A899F0
        case .peach:    return Color(red: 0.949, green: 0.631, blue: 0.533)   // #F2A188
        case .sky:      return Color(red: 0.549, green: 0.745, blue: 0.949)   // #8CBEF2
        case .rose:     return Color(red: 0.941, green: 0.651, blue: 0.745)   // #F0A6BE
        }
    }
}

extension AppThemeColor {
    /// Fuerza el tema a "Azul" una sola vez, para que el color de marca se
    /// vea de inmediato sin depender de que el usuario lo elija a mano en
    /// Ajustes. No vuelve a tocar la preferencia después de esta vez.
    static func migrateToBrandBlueIfNeeded() {
        let key = "didMigrateToBrandBlueTheme"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(AppThemeColor.blue.rawValue, forKey: "appAccentColor")
        defaults.set(true, forKey: key)
    }
}
