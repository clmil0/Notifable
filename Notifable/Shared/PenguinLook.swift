import SwiftUI

/// El pingüino de "Tu perfil" (diseño `Amigos · Mi gasto y tarjeta.dc.html`, 2a).
///
/// Se guarda como índices y no como colores sueltos: así cabe en un JSON de
/// seis números en el respaldo, y si una paleta se afina más adelante todos
/// los pingüinos que la usan se afinan con ella.
struct PenguinLook: Codable, Hashable {
    var breed: Int = 0
    /// 0 = joven (cabeza y ojos más grandes), 1 = adulto.
    var age: Int = 1
    var coat: Int = 0
    var beak: Int = 0
    var accent: Int = 0
    var accessory: Int = 0

    var breedStyle: PenguinBreed { PenguinBreed.all[breed % PenguinBreed.all.count] }
    var coatHex: String { PenguinPalettes.coats[coat % PenguinPalettes.coats.count].hex }
    var beakHex: String { PenguinPalettes.beaks[beak % PenguinPalettes.beaks.count].hex }
    var accentHex: String { PenguinPalettes.accents[accent % PenguinPalettes.accents.count].hex }
    var accessoryStyle: PenguinAccessory { PenguinAccessory(rawValue: accessory % PenguinAccessory.allCases.count) ?? .none }

    /// Cambiar de raza trae sus colores de siempre; después se retocan a mano.
    mutating func setBreed(_ index: Int) {
        let count = PenguinBreed.all.count
        breed = ((index % count) + count) % count
        let base = PenguinBreed.all[breed]
        coat = base.coat
        beak = base.beak
        accent = base.accent
    }

    static func random() -> PenguinLook {
        var look = PenguinLook()
        look.setBreed(Int.random(in: 0..<PenguinBreed.all.count))
        look.age = Int.random(in: 0...1)
        look.accessory = Int.random(in: 0..<PenguinAccessory.allCases.count)
        return look
    }

    static let ageNames = ["Joven", "Adulto"]
}

struct PenguinBreed {
    enum Face { case high, low }
    enum Tuft { case leaf, spikes }
    enum Eyes { case plain, ring27, ring34, iris }
    enum Extra { case none, emperor, chinstrap, gentoo, rockhopper, magellanic }

    let name: String
    let face: Face
    let tuft: Tuft
    let eyes: Eyes
    let extra: Extra
    /// Colores con los que llega la raza: índices en `PenguinPalettes`.
    let coat: Int
    let beak: Int
    let accent: Int

    static let all: [PenguinBreed] = [
        .init(name: "Clásico", face: .high, tuft: .leaf, eyes: .plain, extra: .none, coat: 0, beak: 0, accent: 0),
        .init(name: "Emperador", face: .low, tuft: .leaf, eyes: .ring27, extra: .emperor, coat: 1, beak: 1, accent: 0),
        .init(name: "Adelia", face: .low, tuft: .leaf, eyes: .ring34, extra: .none, coat: 2, beak: 3, accent: 2),
        .init(name: "Barbijo", face: .high, tuft: .leaf, eyes: .plain, extra: .chinstrap, coat: 3, beak: 3, accent: 2),
        .init(name: "Papúa", face: .low, tuft: .leaf, eyes: .ring27, extra: .gentoo, coat: 4, beak: 2, accent: 2),
        .init(name: "Penacho amarillo", face: .low, tuft: .spikes, eyes: .iris, extra: .rockhopper, coat: 5, beak: 2, accent: 1),
        .init(name: "Magallanes", face: .high, tuft: .leaf, eyes: .plain, extra: .magellanic, coat: 6, beak: 4, accent: 2)
    ]
}

enum PenguinAccessory: Int, CaseIterable {
    case none, hat, scarf, glasses

    var name: String {
        switch self {
        case .none: return "Ninguno"
        case .hat: return "Gorro"
        case .scarf: return "Bufanda"
        case .glasses: return "Lentes"
        }
    }
}

enum PenguinPalettes {
    struct Swatch { let name: String; let hex: String }

    static let coats: [Swatch] = [
        .init(name: "Gris", hex: "#7d7d8f"), .init(name: "Carbón", hex: "#2b2d42"),
        .init(name: "Tinta", hex: "#1f2233"), .init(name: "Pizarra", hex: "#3b3f4f"),
        .init(name: "Azulado", hex: "#2f3445"), .init(name: "Grafito", hex: "#2a2d3a"),
        .init(name: "Humo", hex: "#3a3a48"), .init(name: "Café", hex: "#4a3b2a"),
        .init(name: "Jade", hex: "#2f5d4e")
    ]
    static let beaks: [Swatch] = [
        .init(name: "Ámbar", hex: "#f5a623"), .init(name: "Mandarina", hex: "#f28c28"),
        .init(name: "Coral", hex: "#ff6a3d"), .init(name: "Pizarra", hex: "#3d3d4e"),
        .init(name: "Perla", hex: "#c9cdd8")
    ]
    static let accents: [Swatch] = [
        .init(name: "Amarillo", hex: "#ffb627"), .init(name: "Dorado", hex: "#ffd23f"),
        .init(name: "Blanco", hex: "#ffffff"), .init(name: "Menta", hex: "#9be8d8")
    ]
}

/// Color hexadecimal con mezcla en RGB — lo mismo que hacía `color-mix` en el
/// SVG original para los brillos del manto y la sombra del pico.
struct RGBColor {
    let r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(clean, radix: 16) ?? 0
        r = Double((value >> 16) & 0xff) / 255
        g = Double((value >> 8) & 0xff) / 255
        b = Double(value & 0xff) / 255
    }

    /// `amount` es cuánto queda de este color (0.65 = 65 % propio, 35 % `other`).
    func mixed(with other: RGBColor, amount: Double) -> RGBColor {
        RGBColor(r: r * amount + other.r * (1 - amount),
                 g: g * amount + other.g * (1 - amount),
                 b: b * amount + other.b * (1 - amount))
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    static let white = RGBColor(r: 1, g: 1, b: 1)
    static let black = RGBColor(r: 0, g: 0, b: 0)
}
