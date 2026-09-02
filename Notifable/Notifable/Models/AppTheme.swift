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
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }
}
