import SwiftUI

/// Paleta con contraste verificado. Reemplaza a `Color.primary.opacity(0.05)`.
///
/// El problema del diseño anterior: en modo claro `primary.opacity(0.05)` es
/// #F2F2F2 sobre blanco — una diferencia de luminancia de ~4%, invisible en
/// pantalla al sol o con brillo bajo. Y `primary.opacity(0.7)` como texto
/// secundario sobre ese fondo queda por debajo de 4.5:1.
///
/// Aquí las superficies son **opacas** y llevan un borde de 0.5 pt, y el texto
/// secundario usa valores que cumplen AA (≥ 4.5:1 sobre su propia superficie).
struct Palette {

    let scheme: ColorScheme

    init(_ scheme: ColorScheme) { self.scheme = scheme }

    private var dark: Bool { scheme == .dark }

    /// Fondo de pantalla.
    var background: Color { dark ? Color.black : Color.white }

    /// Superficie de tarjeta.
    var surface: Color {
        dark ? Color(red: 0.110, green: 0.110, blue: 0.118)   // #1C1C1E
             : Color(red: 0.969, green: 0.969, blue: 0.976)   // #F7F7F9
    }

    /// Superficie elevada (sheets, menús).
    var surfaceElevated: Color {
        dark ? Color(red: 0.173, green: 0.173, blue: 0.180)   // #2C2C2E
             : Color.white
    }

    /// Borde de 0.5 pt que separa la tarjeta del fondo. Lo que faltaba.
    var hairline: Color {
        dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    /// Separador interno de listas.
    var separator: Color {
        dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    var label: Color { dark ? .white : .black }

    /// Texto secundario legible: #AEAEB2 sobre #1C1C1E = 6.1:1;
    /// #6C6C70 sobre #F7F7F9 = 5.4:1. (Antes: 3.1:1 y 3.6:1.)
    var secondaryLabel: Color {
        dark ? Color(red: 0.682, green: 0.682, blue: 0.698)   // #AEAEB2
             : Color(red: 0.424, green: 0.424, blue: 0.439)   // #6C6C70
    }

    /// Terciario, sólo para marcas de tiempo y placeholders.
    var tertiaryLabel: Color {
        dark ? Color(red: 0.557, green: 0.557, blue: 0.576)
             : Color(red: 0.557, green: 0.557, blue: 0.576)
    }

    /// Relleno de barras de progreso y pistas de gráficos.
    var track: Color {
        dark ? Color.white.opacity(0.13) : Color(red: 0.890, green: 0.890, blue: 0.909)
    }

    var positive: Color { dark ? Color(red: 0.188, green: 0.820, blue: 0.345) : Color(red: 0.114, green: 0.498, blue: 0.235) }
    var negative: Color { dark ? Color(red: 1.0, green: 0.412, blue: 0.380) : Color(red: 0.659, green: 0.118, blue: 0.082) }
    var warning: Color { dark ? Color(red: 1.0, green: 0.624, blue: 0.039) : Color(red: 0.702, green: 0.416, blue: 0.0) }
}

extension EnvironmentValues {
    var palette: Palette {
        Palette(self.colorScheme)
    }
}

extension AppThemeColor {

    /// Color de relleno (botones, barras, chips activos). El color del sistema.
    var fill: Color { color }

    /// Color para **texto e iconos sobre fondo claro**. `systemPurple` sobre
    /// blanco da 3.4:1 y no cumple AA para texto; esta variante sí.
    func onSurface(_ scheme: ColorScheme) -> Color {
        guard scheme == .light else { return tintOnDark }
        switch self {
        case .purple: return Color(red: 0.478, green: 0.235, blue: 0.600)   // #7A3C99
        case .blue:   return Color(red: 0.000, green: 0.349, blue: 0.698)   // #0059B2
        case .green:  return Color(red: 0.114, green: 0.498, blue: 0.235)   // #1D7F3C
        case .orange: return Color(red: 0.702, green: 0.416, blue: 0.000)   // #B36A00
        case .red:    return Color(red: 0.659, green: 0.118, blue: 0.082)   // #A81E15
        }
    }

    /// Variante clara para texto sobre fondo oscuro.
    private var tintOnDark: Color {
        switch self {
        case .purple: return Color(red: 0.847, green: 0.651, blue: 0.941)   // #D8A6F0
        case .blue:   return Color(red: 0.392, green: 0.702, blue: 1.000)
        case .green:  return Color(red: 0.561, green: 0.890, blue: 0.658)
        case .orange: return Color(red: 1.000, green: 0.749, blue: 0.373)
        case .red:    return Color(red: 1.000, green: 0.541, blue: 0.510)
        }
    }

    /// Fondo tenue para chips y banners de acento.
    func softFill(_ scheme: ColorScheme) -> Color {
        color.opacity(scheme == .dark ? 0.20 : 0.14)
    }
}

/// Tarjeta estándar: superficie opaca + borde hairline. Un solo modificador
/// para que ninguna pantalla vuelva a inventar su propio fondo.
struct SurfaceCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 18
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        let palette = Palette(scheme)
        return content
            .padding(padding)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
    }
}

extension View {
    func surfaceCard(radius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(SurfaceCard(radius: radius, padding: padding))
    }
}
