import SwiftUI

/// Los destinos del dashboard único (`1b`).
///
/// Antes eran tres pestañas —Resumen, Análisis, Social— con sub-vistas en una
/// píldora arriba. Ahora todo parte del dashboard y se **entra** a cada cosa
/// desde su tarjeta: Historial, Categorías, Pendientes, Amigos. Lo que antes
/// eran hermanas en la píldora siguen siéndolo dentro de la pantalla a la que
/// se entra: Movimientos ↔ Análisis, Categorías ↔ Etiquetas, Social ↔ Perfil.
enum AppSection: Int, AppSubtab {
    case movements
    case analysis
    case categories
    case tags
    case pending
    case social
    case profile

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .movements:  return "list.bullet"
        case .analysis:   return "chart.bar.fill"
        case .categories: return "square.grid.2x2.fill"
        case .tags:       return "tag.fill"
        case .pending:    return "tray.full.fill"
        case .social:     return "person.2.fill"
        case .profile:    return "person.crop.circle"
        }
    }

    var title: String {
        switch self {
        case .movements:  return "Movimientos"
        case .analysis:   return "Análisis"
        case .categories: return "Categorías"
        case .tags:       return "Etiquetas"
        case .pending:    return "Pendientes"
        case .social:     return "Social"
        case .profile:    return "Mi perfil"
        }
    }

    /// Las que comparten pantalla y se alternan con la píldora de la derecha.
    /// Pendientes va sola: no tiene hermana.
    var siblings: [AppSection] {
        switch self {
        case .movements, .analysis:  return [.movements, .analysis]
        case .categories, .tags:     return [.categories, .tags]
        case .pending:               return [.pending]
        case .social, .profile:      return [.social, .profile]
        }
    }
}

/// La píldora de la derecha del header: sólo íconos, 2 a 4 (`1a`).
///
/// La píldora no lleva texto a propósito. El título de la pantalla lo da el
/// contenido, así que repetirlo arriba sería gastar la franja más valiosa de
/// la pantalla en decir lo que ya se ve.
protocol AppSubtab: CaseIterable, Hashable, Identifiable {
    var icon: String { get }
    /// Para VoiceOver y para las pruebas de interfaz; nunca se dibuja.
    var title: String { get }
}
