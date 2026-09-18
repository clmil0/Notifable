import SwiftUI

/// Los tres destinos del rediseño (`1a`).
///
/// Antes eran cuatro —Resumen, Categorías, Ritmo, Amigos— y cada uno traía su
/// propia barra de filtro de periodo arriba. La regla nueva es una sola:
/// **lo que pasa hoy va en Resumen; todo lo que requiera elegir un periodo va
/// en Análisis**. Categorías y Ritmo dejan de ser destinos y pasan a ser
/// sub-vistas de Análisis; el periodo deja de ser global y vive sólo en
/// Análisis › Historial.
enum AppTab: Int, CaseIterable, Hashable {
    case summary = 0
    case analysis = 1
    case social = 2

    var icon: String {
        switch self {
        case .summary:  return "square.stack.3d.up.fill"
        case .analysis: return "chart.pie.fill"
        case .social:   return "person.2.fill"
        }
    }

    var title: String {
        switch self {
        case .summary:  return "Resumen"
        case .analysis: return "Análisis"
        case .social:   return "Social"
        }
    }
}

// MARK: - Sub-vistas

/// Una entrada de la píldora superior: sólo ícono, con badge opcional.
///
/// La píldora no lleva texto a propósito (`1a`). El título de la pantalla lo
/// da el contenido —en Resumen, el monto grande—, así que repetirlo arriba
/// sería gastar la franja más valiosa de la pantalla en decir lo que ya se ve.
protocol AppSubtab: CaseIterable, Hashable, Identifiable {
    var icon: String { get }
    /// Para VoiceOver y para las pruebas de interfaz; nunca se dibuja.
    var title: String { get }
}

enum SummarySubtab: Int, AppSubtab {
    case today = 0
    case movements = 1
    case balance = 2

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .today:     return "calendar"
        case .movements: return "list.bullet"
        case .balance:   return "arrow.up.arrow.down"
        }
    }

    var title: String {
        switch self {
        case .today:     return "Hoy"
        case .movements: return "Movimientos"
        case .balance:   return "Balance"
        }
    }
}

enum AnalysisSubtab: Int, AppSubtab {
    case pending = 0
    case categories = 1
    case budgets = 2
    case history = 3

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .pending:    return "tray.full.fill"
        case .categories: return "square.grid.2x2.fill"
        case .budgets:    return "target"
        case .history:    return "chart.bar.fill"
        }
    }

    var title: String {
        switch self {
        case .pending:    return "Pendientes"
        case .categories: return "Categorías"
        case .budgets:    return "Presupuestos"
        case .history:    return "Historial"
        }
    }
}

enum SocialSubtab: Int, AppSubtab {
    case activity = 0
    case friends = 1
    case profile = 2

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .activity: return "bolt.fill"
        case .friends:  return "person.2.fill"
        case .profile:  return "person.crop.circle"
        }
    }

    var title: String {
        switch self {
        case .activity: return "Actividad"
        case .friends:  return "Amigos"
        case .profile:  return "Mi perfil"
        }
    }
}

// MARK: - Reglas de visibilidad (`3d`)

/// «Nada vacío se dibuja»: si un destino no tiene nada que decir, no ocupa
/// sitio en la píldora ni en la pantalla.
///
/// Ojo con el efecto secundario: un ícono que aparece y desaparece mueve a sus
/// vecinos de sitio. Por eso el orden es fijo y los condicionales van en los
/// extremos —Pendientes primero, Balance último—, nunca en medio.
struct SubtabVisibility {
    /// Lo que queda por clasificar **este mes**: es lo que cuenta el badge.
    var pendingCount: Int = 0
    /// Queda algo sin clasificar en cualquier periodo. Basta para que
    /// Pendientes exista en la píldora, aunque el mes esté al día y no haya
    /// badge.
    var hasAnyPending: Bool = false
    /// Sólo con un presupuesto definido (general o por categoría). Sin él,
    /// ingresos y «queda» ya viven en Hoy y Balance no aporta nada.
    var hasBudget: Bool = false

    var summary: [SummarySubtab] {
        hasBudget ? [.today, .movements, .balance] : [.today, .movements]
    }

    var analysis: [AnalysisSubtab] {
        hasAnyPending || pendingCount > 0 ? AnalysisSubtab.allCases.map { $0 }
                         : [.categories, .budgets, .history]
    }

    var social: [SocialSubtab] { SocialSubtab.allCases.map { $0 } }

    func badge(for subtab: AnalysisSubtab) -> Int? {
        subtab == .pending && pendingCount > 0 ? pendingCount : nil
    }
}
