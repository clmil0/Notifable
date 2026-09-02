import Testing
import Foundation
@testable import Notifable

/// El presupuesto y el ritmo. Lo que se comprueba aquí es que la tarjeta
/// principal no pueda mostrar un juicio equivocado: ni prorrateos que no cuadran,
/// ni "nan", ni un `Int(...)` con una fracción infinita —que en Swift es un
/// crash, no un cero.
struct BudgetTests {

    static let cal = Period.calendar

    static func month(_ year: Int, _ month: Int) -> Period {
        Period(granularity: .mes, reference: cal.date(from: DateComponents(year: year, month: month, day: 10))!)
    }

    // MARK: - Prorrateo

    @Test("El presupuesto mensual se prorratea por días")
    func prorrateo() {
        let september = Self.month(2026, 9)          // 30 días
        let monthly = 3000.0

        let mes = BudgetStore.target(monthlyBudget: monthly, enabled: true, for: september)
        #expect(Money.equals(mes ?? 0, 3000))

        var week = september
        week.granularity = .semana
        let semana = BudgetStore.target(monthlyBudget: monthly, enabled: true, for: week)
        // 3000 / 30 = 100 al día, 7 días
        #expect(Money.equals(semana ?? 0, 700), "semana = \(semana ?? -1)")

        var day = september
        day.granularity = .dia
        #expect(Money.equals(BudgetStore.target(monthlyBudget: monthly, enabled: true, for: day) ?? 0, 100))

        var year = september
        year.granularity = .anio
        #expect(Money.equals(BudgetStore.target(monthlyBudget: monthly, enabled: true, for: year) ?? 0, 36_000))
    }

    @Test("Sin presupuesto no se inventa una meta")
    func sinPresupuesto() {
        let period = Self.month(2026, 9)
        #expect(BudgetStore.target(monthlyBudget: 0, enabled: true, for: period) == nil)
        #expect(BudgetStore.target(monthlyBudget: 2400, enabled: false, for: period) == nil)
        #expect(BudgetStore.pace(monthlyBudget: 0, enabled: true, for: period, spent: 500) == nil)
    }

    // MARK: - Ritmo

    @Test("El ritmo compara lo gastado con lo transcurrido del periodo")
    func ritmo() {
        // Un mes ya cerrado: transcurrido el 100 %, así que lo esperado es la meta.
        let closed = Self.month(2026, 4)
        let pace = Pace(period: closed, spent: 1200, target: 1000)

        #expect(pace.expectedFraction == 1.0)
        #expect(Money.equals(pace.expectedSpent, 1000))
        #expect(Money.equals(pace.delta, 200))
        #expect(pace.isOverPace)
        #expect(pace.status == .over, "gastar por encima de la meta es .over, no .warning")
        #expect(Money.equals(pace.remaining, 0), "el restante nunca es negativo")
        #expect(Money.equals(pace.projection, 1200), "con el periodo entero transcurrido, proyección = gasto")
    }

    @Test("Por debajo del ritmo el estado es ok y el mensaje lo dice")
    func porDebajoDelRitmo() {
        let closed = Self.month(2026, 4)
        let pace = Pace(period: closed, spent: 400, target: 1000)

        #expect(!pace.isOverPace)
        #expect(pace.status == .ok)
        #expect(Money.equals(pace.remaining, 600))
        #expect(pace.message.contains("bajo de tu ritmo"))
        #expect(!pace.message.contains("nan"))
    }

    @Test("Sin gasto, el mensaje no habla de ritmo")
    func sinGasto() {
        let pace = Pace(period: Self.month(2026, 4), spent: 0, target: 1000)
        #expect(pace.message == "Aún no registras gastos en este periodo.")
        #expect(pace.usedPercent == 0)
        #expect(Money.equals(pace.projection, 0))
    }

    // MARK: - Bordes

    @Test("Un periodo futuro no produce nan, inf ni un Int inválido")
    func periodoFuturo() {
        // elapsedDays == 0 -> elapsedFraction == 0: la división de la proyección
        // sería infinita si no estuviera protegida.
        let future = Period(granularity: .mes,
                            reference: Self.cal.date(byAdding: .month, value: 6, to: Date())!)
        let pace = Pace(period: future, spent: 0, target: 1000)

        #expect(pace.expectedFraction.isFinite)
        #expect(pace.projection.isFinite)
        #expect(pace.usedPercent == 0)
        #expect(pace.expectedPercent >= 0)
        #expect(!Money.format(pace.projection).contains("nan"))
        #expect(!Money.format(pace.delta).contains("-0.00"))
    }

    @Test("El disponible por día se apaga cuando no quedan días")
    func disponiblePorDia() {
        let closed = Self.month(2026, 4)               // ya terminó: 0 días restantes
        let pace = Pace(period: closed, spent: 400, target: 1000)
        #expect(pace.availablePerDay == nil, "sin días restantes no hay 'por día' que repartir")

        // Un periodo en curso sí lo tiene, y reparte el restante sin perder céntimos.
        let current = Period(granularity: .mes, reference: Date())
        let running = Pace(period: current, spent: 0, target: 300)
        if let perDay = running.availablePerDay, current.remainingDays > 0 {
            let repartido = Money.multiply(perDay, by: Double(current.remainingDays))
            #expect(Money.isGreater(repartido, than: 0))
            #expect(!Money.isGreater(repartido, than: 301), "el reparto no puede inventar dinero")
        }
    }

    @Test("La meta usa los días reales del mes, no 30 fijos")
    func mesesDeDistintaLongitud() {
        // Febrero de 2026 tiene 28 días; enero, 31.
        var february = Self.month(2026, 2)
        february.granularity = .dia
        var january = Self.month(2026, 1)
        january.granularity = .dia

        let feb = BudgetStore.target(monthlyBudget: 2800, enabled: true, for: february) ?? 0
        let jan = BudgetStore.target(monthlyBudget: 3100, enabled: true, for: january) ?? 0
        #expect(Money.equals(feb, 100), "2800 / 28 = 100, salió \(feb)")
        #expect(Money.equals(jan, 100), "3100 / 31 = 100, salió \(jan)")
    }
}
