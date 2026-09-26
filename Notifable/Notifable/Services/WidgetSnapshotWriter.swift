import Foundation
import SwiftData
import SwiftUI
import UIKit
import WidgetKit
import AppIntents

/// Mantiene al día el resumen de los widgets.
///
/// Escucha lo mismo que `ConfigBackupManager` —cada guardado de SwiftData y
/// cada cambio de `UserDefaults` (presupuesto, tema, bloqueo)— y agrupa las
/// ráfagas: la sincronización de Gmail guarda decenas de veces seguidas y no
/// tiene sentido recalcular el mes en cada una. Así ninguna pantalla ni el
/// parser de correos tiene que acordarse de avisar a los widgets.
///
/// Sólo recarga los widgets si el JSON cambió: iOS limita las recargas por
/// día cuando la app está en segundo plano.
@MainActor
final class WidgetSnapshotWriter {

    static let shared = WidgetSnapshotWriter()

    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    /// Evita que escribir el resumen dispare otro por `UserDefaults`.
    private var isBuilding = false

    static let debounce: Duration = .seconds(1.5)

    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container

        let center = NotificationCenter.default
        // `Task { @MainActor in … }`: ver la nota de `ConfigBackupManager.startWatching`.
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] note in
            // La caché de amigos no sale en los widgets (`SocialCacheSave`).
            guard !SocialCacheSave.isCacheOnly(note) else { return }
            Task { @MainActor in self?.scheduleRefresh() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
                                            object: UserDefaults.standard, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshInBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.significantTimeChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshInBackground() }
        })

        scheduleRefresh()
    }

    func scheduleRefresh() {
        guard !isBuilding, container != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.refreshInBackground()
        }
    }

    /// Hay un resumen armándose en segundo plano.
    private var isRefreshing = false
    /// Llegó otro cambio mientras tanto: al terminar se arma otra vez.
    private var needsAnotherRefresh = false

    /// Lo pesado —leer todo el historial, los recurrentes y los totales del
    /// mes— en segundo plano. En el hilo principal esto congelaba la app entre
    /// 4 y 9 s tras cada guardado (bitácora del 23/09). Del hilo principal sólo
    /// sale lo que vive ahí: el catálogo de categorías, el tema y los límites.
    func refreshInBackground() {
        pending?.cancel()
        guard !isRefreshing else { needsAnotherRefresh = true; return }
        let container = self.container ?? AppModelContainer.shared
        isRefreshing = true

        // Al pasar a segundo plano iOS suspende la app enseguida: sin este
        // tiempo extra el resumen se quedaría a medias.
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Resumen de widgets") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        Task { @MainActor in
            defer {
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
                isRefreshing = false
                if needsAnotherRefresh {
                    needsAnotherRefresh = false
                    scheduleRefresh()
                }
            }
            let now = Date()
            do {
                let stored = try await Task.detached(priority: .utility) {
                    try Self.readStore(context: ModelContext(container), now: now)
                }.value
                let inputs = Self.inputs(from: stored)
                let changed = try await Task.detached(priority: .utility) {
                    try WidgetSnapshotStore.save(WidgetSnapshotBuilder.build(inputs, now: now))
                }.value
                if changed { WidgetCenter.shared.reloadAllTimelines() }
            } catch {
                Diagnostics.shared.log("Widgets: no se pudo armar o escribir el resumen: \(error)")
            }
            // Las frases de Siri con un gasto rápido ("Registra pasaje en AgruPay")
            // dependen de los nombres guardados.
            NotifableShortcutsProvider.updateAppShortcutParameters()
        }
    }

    /// Sin espera y en el hilo principal. Sólo para los intents de Siri: el
    /// proceso puede suspenderse antes de que termine una tarea en segundo
    /// plano. Todo lo demás va por `refreshInBackground`.
    func refreshNow() {
        pending?.cancel()
        let container = self.container ?? AppModelContainer.shared
        isBuilding = true
        defer { isBuilding = false }

        let snapshot: WidgetSnapshot
        do {
            snapshot = try Self.makeSnapshot(context: container.mainContext, now: Date())
        } catch {
            Diagnostics.shared.log("Widgets: no se pudo armar el resumen: \(error)")
            return
        }

        do {
            if try WidgetSnapshotStore.save(snapshot) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            Diagnostics.shared.log("Widgets: no se pudo escribir el resumen: \(error)")
        }

        NotifableShortcutsProvider.updateAppShortcutParameters()
    }

    // MARK: - Lectura de la base

    static func makeSnapshot(context: ModelContext, now: Date,
                             defaults: UserDefaults = .standard) throws -> WidgetSnapshot {
        let stored = try readStore(context: context, now: now)
        return WidgetSnapshotBuilder.build(inputs(from: stored, defaults: defaults), now: now)
    }

    /// Lo que sale de la base, ya como valores: se puede armar en cualquier
    /// hilo con un `ModelContext` de ese mismo hilo.
    struct StoredData {
        var expenses: [ExpenseSnapshot]
        var incomes: [IncomeSnapshot]
        var usdToPen: Double
        var quickActions: [WidgetSnapshot.QuickAction]
        var pendingRecurringCount: Int
        var nextRecurring: WidgetSnapshot.UpcomingItem?
        var categoryCounts: [String: Int]
    }

    nonisolated static func readStore(context: ModelContext, now: Date) throws -> StoredData {
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        let incomes = try context.fetch(FetchDescriptor<Income>())
        let rules = try context.fetch(FetchDescriptor<RecurringExpense>())
        let quick = try context.fetch(FetchDescriptor<QuickExpense>(sortBy: [SortDescriptor(\.sortIndex)]))

        let usdToPen = ExchangeRateService.storedRate
        let awaiting = RecurringEngine.pending(rules: rules, expenses: expenses, now: now).filter(\.isAwaiting)

        return StoredData(
            expenses: expenses.map(\.accountingSnapshot),
            incomes: incomes.map(\.accountingSnapshot),
            usdToPen: usdToPen,
            quickActions: quick.map {
                WidgetSnapshot.QuickAction(id: $0.id,
                                           label: $0.label,
                                           amountCents: Accounting.penCents(amount: $0.amount, currency: $0.currency,
                                                                            fxRateAtCapture: nil, fallbackRate: usdToPen),
                                           icon: $0.iconName)
            },
            pendingRecurringCount: awaiting.reduce(0) { $0 + $1.dates.count },
            nextRecurring: nextRecurring(rules, now: now, usdToPen: usdToPen),
            categoryCounts: CategoryStyle.usageCounts(expenses)
        )
    }

    /// Ajustes, tema y estilo de cada categoría. Barato, pero en el hilo
    /// principal: `CategoryCatalog` se edita desde ahí. El estilo queda
    /// resuelto en una tabla para que `build` pueda correr en otro hilo.
    static func inputs(from stored: StoredData,
                       defaults: UserDefaults = .standard) -> WidgetSnapshotBuilder.Inputs {
        let accent = AppThemeColor.current
        // Instancia nueva y no `.shared`: lee lo último guardado en `defaults`.
        let limitStore = CategoryBudgetStore(defaults: defaults)
        let categoryBudgets = limitStore.budgets.values.filter(\.hasLimit)
        let categoryNames = CategoryStyle.selectable(counts: stored.categoryCounts)

        var styles: [String: WidgetSnapshotBuilder.Style] = [:]
        let styled = Set(categoryNames).union(stored.categoryCounts.keys)
            .union(categoryBudgets.map(\.category))
            .union([Accounting.unclassified])
        for category in styled {
            styles[category] = WidgetSnapshotBuilder.Style(
                symbol: CategoryStyle.icon(for: category),
                colorHex: CategoryStyle.color(for: category, accent: accent.color).hex(.light))
        }
        let fallback = WidgetSnapshotBuilder.Style(symbol: "bag.fill", colorHex: "808080")

        return WidgetSnapshotBuilder.Inputs(
            expenses: stored.expenses,
            incomes: stored.incomes,
            usdToPen: stored.usdToPen,
            monthlyBudget: defaults.object(forKey: BudgetStore.monthlyBudgetKey) as? Double ?? 0,
            budgetEnabled: defaults.object(forKey: BudgetStore.enabledKey) as? Bool ?? true,
            tracksIncome: defaults.object(forKey: BudgetStore.tracksIncomeKey) as? Bool ?? true,
            hideAmounts: WidgetSnapshotBuilder.hideAmounts(defaults: defaults),
            categoryBudgets: categoryBudgets,
            quickActions: stored.quickActions,
            pendingRecurringCount: stored.pendingRecurringCount,
            nextRecurring: stored.nextRecurring,
            categoryNames: categoryNames,
            theme: WidgetSnapshot.Theme(accentHex: accent.color.hex(.light),
                                        accentDarkHex: accent.color.hex(.dark),
                                        incomeHex: accent.incomeColor(.light).hex(.light),
                                        appearance: widgetAppearance(defaults)),
            style: { styles[$0] ?? fallback },
            penguin: defaults.string(forKey: SocialProfileStore.Keys.penguin)
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONDecoder().decode(PenguinLook.self, from: $0) }
        )
    }

    /// Los widgets siguen el tema de la app: forzado si se eligió claro u
    /// oscuro, el del teléfono en «Automático». Sin clave, oscuro: lo mismo
    /// que pinta `AppAppearanceModifier`.
    private static func widgetAppearance(_ defaults: UserDefaults) -> String? {
        switch AppAppearance(rawValue: defaults.string(forKey: AppAppearance.storageKey) ?? AppAppearance.dark.rawValue) {
        case .light: return "light"
        case .dark: return "dark"
        case .system, nil: return nil
        }
    }

    /// El próximo recurrente en los siete días siguientes que aún no se resolvió.
    nonisolated static func nextRecurring(_ rules: [RecurringExpense], now: Date, usdToPen: Double) -> WidgetSnapshot.UpcomingItem? {
        let cal = Period.calendar
        let today = cal.startOfDay(for: now)
        guard let horizon = cal.date(byAdding: .day, value: 8, to: today) else { return nil }

        return rules
            .compactMap { rule -> (RecurringExpense, Date)? in
                let from = rule.lastResolvedOccurrence
                    .flatMap { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: $0)) }
                    .map { max($0, today) } ?? today
                guard from < horizon,
                      let date = rule.occurrences(in: DateInterval(start: from, end: horizon)).first else { return nil }
                return (rule, date)
            }
            .min { $0.1 < $1.1 }
            .map { rule, date in
                WidgetSnapshot.UpcomingItem(label: Accounting.displayName(rule.merchant),
                                            amountCents: Accounting.penCents(amount: rule.amount, currency: rule.currency,
                                                                             fxRateAtCapture: nil, fallbackRate: usdToPen),
                                            date: date)
            }
    }
}

extension Color {

    /// `RRGGBB` del color resuelto en claro u oscuro. Los widgets no cargan
    /// `AppThemeColor` ni `CategoryCatalog`: reciben el color ya decidido.
    func hex(_ scheme: ColorScheme) -> String {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = UIColor(self).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "808080" }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
