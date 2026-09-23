import SwiftUI

enum AppThemeColor: String, CaseIterable, Identifiable {
    case purple = "Morado"
    case blue = "Azul"
    case green = "Verde"
    case orange = "Naranja"
    case red = "Rojo"
    /// Gama oscura: casi negro en claro. En oscuro sube a un gris grafito,
    /// porque un acento negro sobre fondo negro desaparece (botones, barras,
    /// pestaña activa) — sigue siendo lo bastante oscuro para texto blanco.
    case charcoal = "Carbón"
    // Pastel de un solo color: los mismos tonos de los temas de dos colores,
    // para quien quiere el pastel sin el segundo acento.
    case lilac = "Lila"
    case mint = "Menta"
    case salmon = "Salmón"
    case lightBlue = "Celeste"
    case pink = "Rosado"
    case sand = "Arena"
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
        default: return false
        }
    }

    /// Temas pastel, de uno o dos colores: comparten tintes suaves propios en
    /// claro (el genérico queda muy débil sobre blanco).
    var isPastel: Bool {
        switch self {
        case .purple, .blue, .green, .orange, .red, .charcoal: return false
        default: return true
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
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .red: return .red
        case .charcoal:
            return Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.388, green: 0.388, blue: 0.400, alpha: 1)   // #636366
                    : UIColor(red: 0.173, green: 0.173, blue: 0.180, alpha: 1)   // #2C2C2E
            })
        case .lavender: return Color(red: 0.659, green: 0.600, blue: 0.941)   // #A899F0
        case .peach:    return Color(red: 0.949, green: 0.631, blue: 0.533)   // #F2A188
        case .sky:      return Color(red: 0.549, green: 0.745, blue: 0.949)   // #8CBEF2
        case .rose:     return Color(red: 0.941, green: 0.651, blue: 0.745)   // #F0A6BE
        case .lilac:     return Color(red: 0.659, green: 0.600, blue: 0.941)  // #A899F0
        case .mint:      return Color(red: 0.498, green: 0.847, blue: 0.741)  // #7FD8BD
        case .salmon:    return Color(red: 0.949, green: 0.631, blue: 0.533)  // #F2A188
        case .lightBlue: return Color(red: 0.549, green: 0.745, blue: 0.949)  // #8CBEF2
        case .pink:      return Color(red: 0.941, green: 0.651, blue: 0.745)  // #F0A6BE
        case .sand:      return Color(red: 0.929, green: 0.780, blue: 0.608)  // #EDC79B
        }
    }
}

extension AppThemeColor {

    static let storageKey = "appAccentColor"

    /// El tema guardado. Mismo valor por defecto que los `@AppStorage`.
    static var current: AppThemeColor {
        AppThemeColor(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .blue
    }

    var themeKindLabel: String { isDuotone ? "Dos colores" : "Un color" }

    // MARK: - Intensificar el color del tema (opcional)

    /// Ajustes › Apariencia: tiñe tarjetas y bordes con el tema. Apagado por
    /// defecto — superficies grises neutras y los bordes de acento de siempre.
    static let intenseTintKey = "intenseThemeTint"

    static var usesIntenseTint: Bool {
        UserDefaults.standard.bool(forKey: intenseTintKey)
    }

    // MARK: - Colores de categoría del tema (opcional)

    /// Ajustes › Apariencia: si las categorías sin color elegido a mano toman
    /// su color de una rampa del tema en vez de su color fijo. Apagado por
    /// defecto — cada categoría conserva su color.
    static let themedCategoryColorsKey = "themedCategoryColors"

    static var usesThemedCategoryColors: Bool {
        UserDefaults.standard.bool(forKey: themedCategoryColorsKey)
    }

    /// Rampa de `1c`: acento 1, una variante vecina, acento 2, su vecina y un
    /// acento 1 lavado. En los temas de un color el segundo tono se deriva
    /// (−70° en la rueda, un punto más claro) para que la rampa no repita.
    func categoryRamp(_ scheme: ColorScheme) -> [Color] {
        let acc = color
        let acc2 = isDuotone ? secondaryColor
                             : acc.shiftedHSL(hue: -70, lightness: 0.06, scheme: scheme)
        return [
            acc,
            acc.shiftedHSL(hue: -35, lightness: 0.10, scheme: scheme),
            acc2,
            acc2.shiftedHSL(hue: -30, lightness: 0.10, scheme: scheme),
            acc.shiftedHSL(hue: 25, saturation: -0.15, lightness: 0.16, scheme: scheme),
            acc2.shiftedHSL(hue: 30, saturation: -0.10, lightness: -0.08, scheme: scheme),
            acc.shiftedHSL(hue: 60, lightness: -0.06, scheme: scheme),
            acc2.shiftedHSL(hue: -60, saturation: -0.10, lightness: 0.12, scheme: scheme)
        ]
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
