import Testing
import Foundation
@testable import Notifable

/// «Tu resumen» (`1f`): qué tarjetas salen, con qué cifras, y cuándo el ✦
/// lleva punto.
struct AssistantBriefTests {

    static let cal = Period.calendar

    /// 24 de setiembre de 2026, a mediodía.
    static let now: Date = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!

    static func day(_ month: Int, _ day: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: 10))!
    }

    static func inputs(expenses: [ExpenseSnapshot] = [],
                       upcoming: [UpcomingCharge] = [],
                       debts: [OpenDebt] = []) -> AssistantInputs {
        AssistantInputs(now: now, expenses: expenses, incomes: [], usdToPen: 3.7,
                        upcoming: upcoming, debts: debts)
    }

    static func defaults(_ name: String) -> UserDefaults {
        let suite = UserDefaults(suiteName: "assistant-tests-" + name)!
        suite.removePersistentDomain(forName: "assistant-tests-" + name)
        return suite
    }

    // MARK: - Contra el mes anterior

    @Test func comparaALaMismaAlturaDelMes() {
        let expenses = [
            ExpenseSnapshot(amount: 300, date: Self.day(9, 10), category: "Comida"),
            ExpenseSnapshot(amount: 100, date: Self.day(8, 10), category: "Comida"),
            // Después del 24 de agosto: no cuenta «a esta altura».
            ExpenseSnapshot(amount: 5_000, date: Self.day(8, 28), category: "Transporte")
        ]
        let card = AssistantBrief.comparison(Self.inputs(expenses: expenses))
        #expect(card.text.contains("S/ 200 más que en agosto"))
        #expect(card.text.contains("vienen de Comida"))
        #expect(card.action == .category("Comida"))
    }

    @Test func sinMesAnteriorNoInventaComparacion() {
        let card = AssistantBrief.comparison(Self.inputs(expenses: [
            ExpenseSnapshot(amount: 50, date: Self.day(9, 3), category: "Comida")
        ]))
        #expect(card.text == "Aún no hay gastos de agosto para comparar.")
        #expect(card.action == nil)
    }

    // MARK: - Ritmo y comparación salen siempre

    @Test func ritmoYComparacionSiempre() {
        let kinds = AssistantBrief.cards(Self.inputs()).map(\.kind)
        #expect(kinds == [.rhythm, .comparison])
    }

    // MARK: - Comprometido: sólo en los próximos 3 días

    @Test func comprometidoSoloSiEsInminente() {
        let soon = UpcomingCharge(id: UUID(), name: "Spotify", amount: 20.90, currency: "PEN", date: Self.day(9, 25))
        let later = UpcomingCharge(id: UUID(), name: "Gimnasio", amount: 120, currency: "PEN", date: Self.day(9, 29))

        let card = AssistantBrief.committed(Self.inputs(upcoming: [soon, later]))
        #expect(card.map { AssistantBrief.tidy($0.text) } == "Mañana te cobran Spotify, S/ 20.90.")
        #expect(AssistantBrief.committed(Self.inputs(upcoming: [later])) == nil)
    }

    // MARK: - Amigos: sólo deudas de 7 días o más

    @Test func amigosSoloConDeudaVieja() {
        let old = OpenDebt(id: UUID(), name: "Cena", outstanding: 45, date: Self.day(9, 12))
        let fresh = OpenDebt(id: UUID(), name: "Taxi", outstanding: 10, date: Self.day(9, 22))

        let card = AssistantBrief.friends(Self.inputs(debts: [fresh, old]))
        #expect(card?.text == "Te deben S/ 45 de «Cena» desde hace 12 días.")
        #expect(card?.action == .reminder(old.id))
        #expect(AssistantBrief.friends(Self.inputs(debts: [fresh])) == nil)
    }

    // MARK: - Punto del ✦

    @Test func puntoHastaAbrirYConTarjetaNueva() {
        let seen = AssistantSeenState(defaults: Self.defaults("seen"))
        let base = AssistantBrief.cards(Self.inputs())
        #expect(seen.hasNews(base))

        seen.markSeen(base)
        #expect(!seen.hasNews(base))

        let debt = OpenDebt(id: UUID(), name: "Cena", outstanding: 45, date: Self.day(9, 1))
        let withFriend = AssistantBrief.cards(Self.inputs(debts: [debt]))
        #expect(seen.hasNews(withFriend))
    }

    // MARK: - La IA no cambia cifras

    @Test func reescrituraConservaCifras() {
        let original = "Mañana te cobran Spotify, S/ 20.90."
        #expect(AssistantAI.keepsFigures(original: original, rewritten: "Ojo: mañana Spotify te cobra S/ 20.90."))
        #expect(!AssistantAI.keepsFigures(original: original, rewritten: "Mañana te cobran Spotify, S/ 21."))
        #expect(!AssistantAI.keepsFigures(original: original, rewritten: "Mañana te cobran Spotify, S/ 20.90 y S/ 5."))
    }

    @Test func ordenaEspaciosDeMonto() {
        #expect(AssistantBrief.tidy("S/\u{00A0} 2.50") == "S/ 2.50")
    }

    // MARK: - Temas recientes (Apariencia 1c)

    @Test func temasRecientesNoSaltanBajoElDedo() {
        let defaults = Self.defaults("recent")
        defaults.set(AppThemeColor.blue.rawValue, forKey: AppThemeColor.storageKey)
        let first = AppThemeColor.recent(defaults: defaults)
        #expect(first.count == 6)

        // Uno que ya está en la fila no se mueve.
        AppThemeColor.noteUsed(.green, defaults: defaults)
        #expect(AppThemeColor.recent(defaults: defaults) == first)

        // Uno nuevo entra primero y empuja al último.
        defaults.set(AppThemeColor.sand.rawValue, forKey: AppThemeColor.storageKey)
        AppThemeColor.noteUsed(.sand, defaults: defaults)
        let after = AppThemeColor.recent(defaults: defaults)
        #expect(after.first == .sand)
        #expect(after.count == 6)
        #expect(!after.contains(first.last!))
    }
}
