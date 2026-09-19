import SwiftUI

/// El personaje de "Tu perfil" (diseño `Amigos · Mi gasto y tarjeta.dc.html`, 2a):
/// un pingüino o uno de los animales del kit, con hasta un objeto por zona.
///
/// Se guarda como índices y no como colores sueltos: así cabe en un JSON
/// corto en el respaldo, y si una paleta se afina más adelante todos los
/// personajes que la usan se afinan con ella. El nombre viene de cuando sólo
/// había pingüinos; cambiarlo movería el JSON de respaldos, caché y servidor.
struct PenguinLook: Hashable {
    /// `nil` = pingüino; si no, el id de un `AvatarAnimal`.
    var species: String? = nil

    // Pingüino
    var breed: Int = 0
    /// 0 = joven (cabeza y ojos más grandes), 1 = adulto.
    var age: Int = 1
    var coat: Int = 0
    var beak: Int = 0
    var accent: Int = 0

    // Animal: índices en `AvatarPalettes`; 0 = el color del diseño.
    var fur: Int = 0
    var nose: Int = 0
    var mark: Int = 0

    /// Ids de `AvatarItem`, como mucho uno por zona.
    var items: [String] = []

    var animal: AvatarAnimal? { AvatarCatalog.animal(species) }
    var isPenguin: Bool { animal == nil }
    /// "Emperador", "Zorro"…: lo que se lee en accesibilidad y en el editor.
    var speciesName: String { animal?.name ?? "Pingüino \(breedStyle.name)" }

    var breedStyle: PenguinBreed { PenguinBreed.all[breed % PenguinBreed.all.count] }
    var coatHex: String { PenguinPalettes.coats[coat % PenguinPalettes.coats.count].hex }
    var beakHex: String { PenguinPalettes.beaks[beak % PenguinPalettes.beaks.count].hex }
    var accentHex: String { PenguinPalettes.accents[accent % PenguinPalettes.accents.count].hex }

    var furHex: String { Self.pick(AvatarPalettes.fur, fur, original: animal?.fur) }
    var noseHex: String { Self.pick(AvatarPalettes.nose, nose, original: animal?.nose) }
    var markHex: String { Self.pick(AvatarPalettes.mark, mark, original: animal?.mark) }

    /// Las variables CSS del SVG del animal.
    var animalColors: [String: RGBColor] {
        ["pelo": RGBColor(hex: furHex), "pico": RGBColor(hex: noseHex), "acento": RGBColor(hex: markHex)]
    }

    private static func pick(_ swatches: [AvatarPalettes.Swatch], _ index: Int, original: String?) -> String {
        let hex = swatches[((index % swatches.count) + swatches.count) % swatches.count].hex
        return hex.isEmpty ? (original ?? "#9a9cae") : hex
    }

    var equipped: [AvatarItem] { items.compactMap(AvatarCatalog.item) }

    func item(in zone: AvatarZone) -> AvatarItem? {
        equipped.first { $0.zone == zone }
    }

    /// Pone `item` en su zona (quitando lo que hubiera), o la vacía con `nil`.
    mutating func wear(_ item: AvatarItem?, in zone: AvatarZone) {
        items.removeAll { AvatarCatalog.item($0)?.zone == zone }
        if let item, item.zone == zone { items.append(item.id) }
    }

    /// Cambiar de raza trae sus colores de siempre; después se retocan a mano.
    mutating func setBreed(_ index: Int) {
        let count = PenguinBreed.all.count
        breed = ((index % count) + count) % count
        let base = PenguinBreed.all[breed]
        coat = base.coat
        beak = base.beak
        accent = base.accent
    }

    /// Cambiar de especie trae sus colores originales; los objetos se quedan.
    mutating func setSpecies(_ id: String?) {
        species = AvatarCatalog.animal(id)?.id
        fur = 0
        nose = 0
        mark = 0
    }

    static func random() -> PenguinLook {
        var look = PenguinLook()
        look.setBreed(Int.random(in: 0..<PenguinBreed.all.count))
        look.age = Int.random(in: 0...1)
        // El pingüino cuenta como una especie más.
        let species = [nil] + AvatarCatalog.animals.map { Optional($0.id) }
        look.setSpecies(species.randomElement() ?? nil)
        for zone in AvatarZone.allCases where Double.random(in: 0..<1) < 0.4 {
            look.wear(AvatarCatalog.items(in: zone).randomElement(), in: zone)
        }
        return look
    }

    static let ageNames = ["Joven", "Adulto"]

    /// Lo que entiende una versión anterior de la app, que sólo sabe de
    /// pingüinos: se manda en la columna `penguin` de `profiles`.
    var legacyPenguin: PenguinLook {
        var look = self
        look.species = nil
        look.fur = 0
        look.nose = 0
        look.mark = 0
        return look
    }
}

// MARK: - JSON

extension PenguinLook: Codable {
    private enum CodingKeys: String, CodingKey {
        case species, breed, age, coat, beak, accent, fur, nose, mark, items
        /// El accesorio único de antes (0 nada, 1 gorro, 2 bufanda, 3 lentes).
        /// Se sigue escribiendo para las versiones anteriores.
        case accessory
    }

    /// Todo opcional: un JSON viejo (sin especie ni objetos) o uno de una
    /// versión más nueva (con campos que aún no existen) se lee igual.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        species = try c.decodeIfPresent(String.self, forKey: .species)
        breed = try c.decodeIfPresent(Int.self, forKey: .breed) ?? 0
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? 1
        coat = try c.decodeIfPresent(Int.self, forKey: .coat) ?? 0
        beak = try c.decodeIfPresent(Int.self, forKey: .beak) ?? 0
        accent = try c.decodeIfPresent(Int.self, forKey: .accent) ?? 0
        fur = try c.decodeIfPresent(Int.self, forKey: .fur) ?? 0
        nose = try c.decodeIfPresent(Int.self, forKey: .nose) ?? 0
        mark = try c.decodeIfPresent(Int.self, forKey: .mark) ?? 0
        if let items = try c.decodeIfPresent([String].self, forKey: .items) {
            self.items = items
        } else {
            let legacy = try c.decodeIfPresent(Int.self, forKey: .accessory) ?? 0
            items = Self.legacyItems[legacy].map { [$0] } ?? []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(species, forKey: .species)
        try c.encode(breed, forKey: .breed)
        try c.encode(age, forKey: .age)
        try c.encode(coat, forKey: .coat)
        try c.encode(beak, forKey: .beak)
        try c.encode(accent, forKey: .accent)
        try c.encode(fur, forKey: .fur)
        try c.encode(nose, forKey: .nose)
        try c.encode(mark, forKey: .mark)
        try c.encode(items, forKey: .items)
        try c.encode(legacyAccessory, forKey: .accessory)
    }

    /// Los tres accesorios de antes, en sus equivalentes del kit.
    private static let legacyItems: [Int: String] = [1: "chullo", 2: "bufanda", 3: "lentes"]

    /// El accesorio de antes que más se parece a lo que lleva puesto.
    private var legacyAccessory: Int {
        if item(in: .cabeza) != nil { return 1 }
        if item(in: .cuello) != nil { return 2 }
        if item(in: .cara) != nil { return 3 }
        return 0
    }
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
struct RGBColor: Equatable {
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
