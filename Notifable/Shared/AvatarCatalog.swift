import Foundation

/// Dónde se lleva un objeto. Uno por zona: un gorro y unos lentes, sí; dos
/// gorros, no. El orden es también el de dibujo (lo de la cabeza, encima).
enum AvatarZone: String, CaseIterable, Identifiable {
    case cabeza, cara, cuello, cuerpo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cabeza: return "Cabeza"
        case .cara: return "Cara"
        case .cuello: return "Cuello"
        case .cuerpo: return "Cuerpo"
        }
    }
}

/// Un animal del kit (`output/animales`). Sus colores de siempre son los del
/// diseño; `PenguinLook.fur/nose/mark` en 0 los respetan.
struct AvatarAnimal: Identifiable {
    let id: String
    let name: String
    let fur: String
    let nose: String
    let mark: String

    var scene: SVGScene? { AvatarCatalog.scene(id) }
}

/// Un objeto del kit. Casi todos son una sola capa delante del animal; la
/// capa de héroe tiene además una detrás (`z < 0`).
struct AvatarItem: Identifiable {
    struct Layer {
        /// Clave en `AvatarArtwork.svg`.
        let svg: String
        /// Menor que 0: detrás del animal. Si no: 1 cuerpo, 2 cuello, 3 cara, 4 cabeza.
        let z: Int
    }

    let id: String
    let name: String
    let zone: AvatarZone
    let color: String
    let color2: String
    let layers: [Layer]

    var colors: [String: RGBColor] {
        ["objeto": RGBColor(hex: color), "objeto2": RGBColor(hex: color2)]
    }
}

enum AvatarCatalog {
    /// Id con el que se guarda el pingüino en la lista de especies del editor.
    static let penguinID = "pinguino"

    static let animals: [AvatarAnimal] = AvatarArtwork.animals
    static let items: [AvatarItem] = AvatarArtwork.items

    static func animal(_ id: String?) -> AvatarAnimal? {
        guard let id else { return nil }
        return animals.first { $0.id == id }
    }

    static func item(_ id: String) -> AvatarItem? {
        items.first { $0.id == id }
    }

    static func items(in zone: AvatarZone) -> [AvatarItem] {
        items.filter { $0.zone == zone }
    }

    /// Cada SVG se lee una sola vez, la primera vez que se dibuja.
    static func scene(_ key: String) -> SVGScene? { scenes[key] ?? nil }

    /// Lee todos los SVG fuera del hilo principal, para que el primer avatar
    /// que se dibuje no tenga que esperar a que se lean.
    static func prewarm() {
        Task.detached(priority: .utility) { _ = scenes.count }
    }

    private static let scenes: [String: SVGScene?] =
        AvatarArtwork.svg.mapValues { SVGScene(svg: $0) }
}

/// Colores para retocar un animal. El primero de cada lista es «Original»:
/// el color con el que el animal viene diseñado (`hex` vacío).
enum AvatarPalettes {
    typealias Swatch = PenguinPalettes.Swatch

    static let original = "Original"

    static let fur: [Swatch] = [
        .init(name: original, hex: ""),
        .init(name: "Miel", hex: "#d9a066"), .init(name: "Naranja", hex: "#f4a259"),
        .init(name: "Dorado", hex: "#f2c14e"), .init(name: "Zanahoria", hex: "#ef6f2e"),
        .init(name: "Chocolate", hex: "#8d5b3e"), .init(name: "Nieve", hex: "#f7f7fb"),
        .init(name: "Lavanda", hex: "#e8e3f2"), .init(name: "Ceniza", hex: "#9a9cae"),
        .init(name: "Crema", hex: "#f5ead8"), .init(name: "Rosa", hex: "#f9b8c9"),
        .init(name: "Menta", hex: "#a8e6cf"), .init(name: "Cielo", hex: "#9ecbff"),
        .init(name: "Carbón", hex: "#4a4a5a")
    ]
    static let nose: [Swatch] = [
        .init(name: original, hex: ""),
        .init(name: "Tinta", hex: "#2b2238"), .init(name: "Rosa", hex: "#f28fa0"),
        .init(name: "Café", hex: "#7a4a3a"), .init(name: "Coral", hex: "#ff6a3d"),
        .init(name: "Pizarra", hex: "#3b3848")
    ]
    static let mark: [Swatch] = [
        .init(name: original, hex: ""),
        .init(name: "Canela", hex: "#8a5a3b"), .init(name: "Tostado", hex: "#c8652a"),
        .init(name: "Tinta", hex: "#2b2233"), .init(name: "Arena", hex: "#e3b98f"),
        .init(name: "Blanco", hex: "#f4f4f8"), .init(name: "Fucsia", hex: "#e0457b"),
        .init(name: "Rosa", hex: "#f6a6c1"), .init(name: "Menta", hex: "#52b788")
    ]
}
