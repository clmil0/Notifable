import Foundation
import SwiftData
import UIKit

/// Mantiene al día lo que les compartes a tus amigos.
///
/// `friend_shares` guarda **montos**, no una regla: el total del mes y el de
/// cada categoría marcada, calculados en el teléfono (lo no marcado nunca sale
/// de él). Antes sólo se subían al tocar los interruptores de un amigo, así
/// que él veía para siempre la cifra de ese momento aunque siguieras
/// gastando. Ahora, igual que `WidgetSnapshotWriter`, se escucha cada guardado
/// de SwiftData y, pasada la ráfaga, se vuelve a calcular el mes y se sube lo
/// que haya cambiado.
///
/// Sólo escribe si algo cambió de verdad (al céntimo): guardar la caché de
/// compartidos también dispara `didSave`, y sin esa comparación sería un
/// bucle. Al empezar un mes nuevo el servidor no tiene fila todavía, y se
/// publica con lo último que elegiste (`SocialProfileStore`).
@MainActor
final class ShareAutoSync {

    static let shared = ShareAutoSync()

    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var isSyncing = false
    /// Llegó otro cambio mientras se subía el anterior.
    private var needsAnotherPass = false

    static let debounce: Duration = .seconds(2)

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        })
        // Al volver a la app (y al cambiar de día o de mes): puede haber
        // gastos que se guardaron sin red, o un mes nuevo sin publicar.
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        })
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleSync() }
        })

        scheduleSync()
    }

    func scheduleSync() {
        guard container != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let container else { return }
        guard !isSyncing else { needsAnotherPass = true; return }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            needsAnotherPass = false
            await syncOnce(context: container.mainContext)
        } while needsAnotherPass
    }

    private func syncOnce(context: ModelContext) async {
        guard SupabaseAuthManager.shared.isReady else { return }
        let manager = FriendsManager.shared
        guard !manager.friends.isEmpty else { return }
        // Sin saber qué hay publicado este mes no se escribe nada: el
        // servidor manda sobre lo elegido.
        guard await manager.ensureCurrentOutgoing() else { return }

        let totals = Self.currentTotals(context: context)
        let social = SocialProfileStore.shared

        for friend in manager.friends {
            let shareTotal: Bool
            let categories: [String]
            if let row = manager.myShare(toward: friend.id) {
                shareTotal = row.shareTotal
                categories = row.shareCategories
            } else {
                let remembered = social.preferences(for: friend.id)
                shareTotal = remembered.sharedTotal
                categories = remembered.sharedCategories
            }
            guard shareTotal || !categories.isEmpty else { continue }

            let amounts = totals.byCategory.map {
                FriendShareRow.CategoryAmount(name: $0.category, amount: $0.total)
            }
            let current = manager.myShare(toward: friend.id)
            guard Self.differs(current, shareTotal: shareTotal, categories: categories,
                               total: totals.spent, amounts: amounts) else { continue }

            await manager.setShare(viewerID: friend.id,
                                   shareTotal: shareTotal,
                                   categories: categories,
                                   totalAmount: totals.spent,
                                   categoryTotals: amounts)
        }
    }

    /// El mismo cálculo que enseña Social (`SocialHubView.totals`): el mes en
    /// curso, sin ingresos.
    static func currentTotals(context: ModelContext, now: Date = Date()) -> PeriodTotals {
        let month = Period(granularity: .mes, reference: now)
        let window = month.dataWindow()
        let start = window.start
        let end = window.end
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(
            predicate: #Predicate<Expense> { $0.date >= start && $0.date < end }))) ?? []
        return Accounting.totals(expenses: expenses, incomes: [], period: month,
                                 usdToPen: ExchangeRateService.shared.usdToPenRate)
    }

    /// Si lo publicado ya no es lo que saldría hoy. Al céntimo: el servidor
    /// guarda `numeric` y lo devuelve con otra representación en coma flotante.
    static func differs(_ row: FriendShareRow?,
                        shareTotal: Bool,
                        categories: [String],
                        total: Double,
                        amounts: [FriendShareRow.CategoryAmount]) -> Bool {
        guard let row else { return true }
        let wantedTotal = shareTotal ? Money.cents(total) : nil
        let publishedTotal = row.totalAmount.map(Money.cents)
        if wantedTotal != publishedTotal { return true }

        func byName(_ list: [FriendShareRow.CategoryAmount]) -> [String: Int] {
            Dictionary(list.map { ($0.name, Money.cents($0.amount)) }, uniquingKeysWith: +)
        }
        let wanted = byName(amounts.filter { categories.contains($0.name) })
        return wanted != byName(row.categoryTotals)
    }
}
