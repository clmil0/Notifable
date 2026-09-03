import SwiftUI

enum AppThemeColor: String, CaseIterable, Identifiable {
    case purple = "Morado"
    case blue = "Azul"
    case green = "Verde"
    case orange = "Naranja"
    case red = "Rojo"
    
    var id: String { self.rawValue }
    
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
