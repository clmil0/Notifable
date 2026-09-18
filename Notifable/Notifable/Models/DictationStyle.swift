import Foundation

/// Cómo se anima la escucha del dictado por voz (diseño «Dictado por voz»).
enum DictationStyle: String, CaseIterable {
    /// `1a`: barras que siguen el volumen. Por defecto.
    case bars
    /// `1c`: una forma orgánica que respira detrás del micrófono.
    case blob

    static let storageKey = "dictationAnimation"

    static var current: DictationStyle {
        DictationStyle(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .bars
    }
}
