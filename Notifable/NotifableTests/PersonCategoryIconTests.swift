import Testing
@testable import Notifable

/// Categorías que son una persona: nombre, parentesco o un niño.
struct PersonCategoryIconTests {

    @Test("Nombres de mujer y de hombre, con o sin tilde")
    func nombres() {
        #expect(PersonCategoryIcon.icon(for: "María") == PersonCategoryIcon.woman)
        #expect(PersonCategoryIcon.icon(for: "maria jose") == PersonCategoryIcon.woman)
        #expect(PersonCategoryIcon.icon(for: "Gastos de Lucía") == PersonCategoryIcon.woman)
        #expect(PersonCategoryIcon.icon(for: "Juan") == PersonCategoryIcon.man)
        #expect(PersonCategoryIcon.icon(for: "JOSÉ LUIS") == PersonCategoryIcon.man)
    }

    @Test("Padre, madre y parientes")
    func parentesco() {
        #expect(PersonCategoryIcon.icon(for: "Mamá") == PersonCategoryIcon.woman)
        #expect(PersonCategoryIcon.icon(for: "Regalos para mi madre") == PersonCategoryIcon.woman)
        #expect(PersonCategoryIcon.icon(for: "Papá") == PersonCategoryIcon.man)
        #expect(PersonCategoryIcon.icon(for: "padre") == PersonCategoryIcon.man)
        #expect(PersonCategoryIcon.icon(for: "Abuelo") == PersonCategoryIcon.man)
    }

    @Test("Hijos y niños mandan sobre el género")
    func ninos() {
        #expect(PersonCategoryIcon.icon(for: "Hijo") == PersonCategoryIcon.child)
        #expect(PersonCategoryIcon.icon(for: "Pensión de mi hija") == PersonCategoryIcon.child)
        #expect(PersonCategoryIcon.icon(for: "Niños") == PersonCategoryIcon.child)
        #expect(PersonCategoryIcon.icon(for: "Bebé de Carla") == PersonCategoryIcon.child)
    }

    @Test("Lo que no es persona no cambia, y el catálogo de palabras gana")
    func sinFalsosPositivos() {
        #expect(PersonCategoryIcon.icon(for: "Supermercado") == nil)
        #expect(PersonCategoryIcon.icon(for: "") == nil)
        #expect(CategoryStyle.defaultIcon(for: "Luz") == "bolt.fill")
        #expect(CategoryStyle.defaultIcon(for: "Rosa") == PersonCategoryIcon.woman)
        #expect(CategoryStyle.defaultIcon(for: "Mi hijo") == PersonCategoryIcon.child)
    }
}
