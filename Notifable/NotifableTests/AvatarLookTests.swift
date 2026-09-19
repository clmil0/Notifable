import Foundation
import Testing
@testable import Notifable

/// El personaje viaja como JSON a respaldos, caché, widgets y Supabase: un
/// JSON de antes (sólo pingüinos) y uno de ahora (animales y objetos) se
/// tienen que leer en cualquier versión.
struct AvatarLookTests {

    private func decode(_ json: String) throws -> PenguinLook {
        try JSONDecoder().decode(PenguinLook.self, from: Data(json.utf8))
    }

    @Test func legacyPenguinKeepsItsAccessory() throws {
        let look = try decode(#"{"breed":1,"age":0,"coat":2,"beak":3,"accent":1,"accessory":2}"#)
        #expect(look.isPenguin)
        #expect(look.breed == 1 && look.age == 0 && look.coat == 2)
        #expect(look.item(in: .cuello)?.id == "bufanda")
    }

    @Test func roundTripKeepsSpeciesAndItems() throws {
        var look = PenguinLook()
        look.setSpecies("zorro")
        look.fur = 3
        look.wear(AvatarCatalog.item("corona"), in: .cabeza)
        look.wear(AvatarCatalog.item("capa-heroe"), in: .cuerpo)
        let data = try JSONEncoder().encode(look)
        #expect(try JSONDecoder().decode(PenguinLook.self, from: data) == look)
    }

    /// Lo que decodifica una versión anterior: las seis claves obligatorias.
    @Test func encodingStillCarriesTheLegacyKeys() throws {
        var look = PenguinLook()
        look.setSpecies("gato")
        look.wear(AvatarCatalog.item("gafas-sol"), in: .cara)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(look.legacyPenguin)) as? [String: Any]
        for key in ["breed", "age", "coat", "beak", "accent", "accessory"] {
            #expect(object?[key] is Int, "falta \(key)")
        }
        #expect(object?["accessory"] as? Int == 3)
        #expect(object?["species"] == nil)
    }

    @Test func oneItemPerZone() {
        var look = PenguinLook()
        look.wear(AvatarCatalog.item("corona"), in: .cabeza)
        look.wear(AvatarCatalog.item("gorra"), in: .cabeza)
        look.wear(AvatarCatalog.item("lentes"), in: .cara)
        #expect(look.items.sorted() == ["gorra", "lentes"])
        look.wear(nil, in: .cabeza)
        #expect(look.items == ["lentes"])
    }

    @Test func unknownSpeciesFallsBackToPenguin() throws {
        let look = try decode(#"{"species":"dragon","breed":2}"#)
        #expect(look.isPenguin)
        #expect(look.breed == 2)
    }

    @Test func originalColorsComeFromTheDesign() {
        var look = PenguinLook()
        look.setSpecies("panda")
        #expect(look.furHex == "#f7f7fb")
        look.fur = 1
        #expect(look.furHex == AvatarPalettes.fur[1].hex)
    }

    @Test func everySVGParsesIntoShapes() {
        for (key, _) in AvatarArtwork.svg {
            let scene = AvatarCatalog.scene(key)
            #expect(scene != nil, "no se pudo leer \(key)")
            #expect(scene?.nodes.isEmpty == false, "\(key) sin figuras")
        }
        for animal in AvatarCatalog.animals { #expect(animal.scene != nil) }
        for item in AvatarCatalog.items {
            for layer in item.layers { #expect(AvatarCatalog.scene(layer.svg) != nil, "\(item.id): \(layer.svg)") }
        }
    }

    @Test func darkEyePatchesKeepTheirRing() {
        #expect(AvatarCatalog.scene("panda")?.eyeRing == 28)
        #expect(AvatarCatalog.scene("perro")?.eyeRing == nil)
    }
}
