import SwiftUI

/// Icono y color de cada fuente de ingreso, en un solo sitio — igual que
/// `CategoryStyle` para gastos. Antes vivía sólo dentro de `DashboardView`;
/// `IncomeDetailsView` necesita el mismo mapeo para la cabecera del detalle.
enum IncomeStyle {

    /// `accent` es el color de "ingreso" del tema (Acento 2 en temas pastel,
    /// verde en los demás). Sólo lo usa el caso genérico: Plin/Yape/BBVA son
    /// colores de marca y no deben cambiar con el tema.
    static func iconAndColor(for income: Income, accent: Color) -> (Color, String) {
        switch income.source {
        case "Plin":
            return (Color(red: 0, green: 0.7, blue: 0.9), "plin_icon")
        case "Yape":
            return (Color(red: 0.5, green: 0, blue: 0.5), "yape_icon")
        case "BBVA":
            return (Color(red: 0.0, green: 0.27, blue: 0.51), "bbva_icon")
        case "Efectivo":
            return (.yellow, "banknote.fill")
        default:
            return (accent, "arrow.down.left.circle.fill")
        }
    }
}
