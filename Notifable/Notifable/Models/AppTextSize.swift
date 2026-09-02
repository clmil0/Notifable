import SwiftUI

/// Tamaño de letra de toda la app.
///
/// La escala tipográfica sigue siendo la del sistema (`.subheadline`, `.headline`,
/// `.title3`…); lo que cambia es el `DynamicTypeSize` con el que se resuelve. Por
/// eso "Sistema" no fija nada: respeta lo que el usuario tenga en Ajustes de iOS,
/// que es lo correcto por accesibilidad. Las otras opciones lo sobreescriben.
enum AppTextSize: String, CaseIterable, Identifiable {
    case compacto = "Compacto"
    case pequeno = "Pequeño"
    case sistema = "Sistema"
    case grande = "Grande"

    var id: String { rawValue }

    static let storageKey = "appTextSize"

    /// `nil` = no sobreescribir, hereda el ajuste de iOS.
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .compacto: return .xSmall
        case .pequeno: return .small
        case .sistema: return nil
        case .grande: return .xLarge
        }
    }

    /// Los dos únicos tamaños literales del diseño —el monto grande de Resumen y
    /// el del detalle— no los toca `DynamicTypeSize`, porque `.system(size:)` es
    /// un valor fijo. Se escalan aquí para que "Compacto" encoja de verdad todo
    /// y no quede una cifra enorme sobre texto pequeño.
    var amountScale: CGFloat {
        switch self {
        case .compacto: return 0.82
        case .pequeno: return 0.91
        case .sistema: return 1.0
        case .grande: return 1.08
        }
    }
}

/// Aplica el tamaño elegido. Se pone en la raíz y en cada sheet: un sheet crea su
/// propia jerarquía de presentación, así que conviene no dar por hecho que el
/// entorno viaja hasta él.
struct AppTextSizeModifier: ViewModifier {
    @AppStorage(AppTextSize.storageKey) private var raw = AppTextSize.sistema.rawValue

    func body(content: Content) -> some View {
        let size = AppTextSize(rawValue: raw)?.dynamicTypeSize
        Group {
            if let size {
                content.dynamicTypeSize(size)
            } else {
                content
            }
        }
    }
}

extension View {
    func appTextSize() -> some View { modifier(AppTextSizeModifier()) }
}

/// Para los dos tamaños literales.
@propertyWrapper
struct ScaledAmountFont: DynamicProperty {
    @AppStorage(AppTextSize.storageKey) private var raw = AppTextSize.sistema.rawValue
    private let base: CGFloat

    init(_ base: CGFloat) { self.base = base }

    var wrappedValue: CGFloat {
        base * (AppTextSize(rawValue: raw)?.amountScale ?? 1.0)
    }
}
