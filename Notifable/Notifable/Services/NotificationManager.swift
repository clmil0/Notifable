import Foundation
import SwiftData
import UIKit
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {}

    /// Se pide al arrancar (con el onboarding ya visto). Antes sólo lo pedía
    /// el menú de marcar "por cobrar", y esa llamada se fue con el rediseño de
    /// las filas: en una instalación nueva el permiso no se pedía nunca, así
    /// que iOS descartaba en silencio todos los avisos.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                Diagnostics.shared.log("Notificaciones: error pidiendo permiso: \(error.localizedDescription)")
            } else {
                Diagnostics.shared.log("Notificaciones: permiso \(granted ? "concedido" : "denegado")")
            }
        }
    }

    /// Sin delegado, iOS no muestra nada si la app está abierta, y el aviso de
    /// límite se dispara justo al registrar un gasto: casi siempre con la app
    /// en primer plano.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // MARK: - Vigilancia

    private var container: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    /// Igual que `WidgetSnapshotWriter`: escucha cada guardado de SwiftData y
    /// recalcula los avisos que dependen de los datos (cobros pendientes y
    /// límites por categoría). Así da igual si el gasto llegó del correo, de
    /// Siri o del formulario; ninguna vista tiene que acordarse de avisar.
    @MainActor
    func start(container: ModelContainer) {
        UNUserNotificationCenter.current().delegate = self
        guard self.container == nil else { return }
        self.container = container

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { _ in
            Task { @MainActor in NotificationManager.shared.scheduleRefresh() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { _ in
            Task { @MainActor in NotificationManager.shared.scheduleRefresh() }
        })
        scheduleRefresh()
    }

    @MainActor
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    @MainActor
    private func refreshNow() {
        guard let context = container?.mainContext else { return }
        let defaults = UserDefaults.standard

        let debtDescriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.isDebt == true })
        let hasDebts = ((try? context.fetchCount(debtDescriptor)) ?? 0) > 0
        updateDebtNotification(hasDebts: hasDebts)

        let month = Period(granularity: .mes, reference: Date())
        let range = month.interval
        let start = range.start, end = range.end
        let monthDescriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let monthExpenses = (try? context.fetch(monthDescriptor)) ?? []
        let spent = Accounting.totals(expenses: monthExpenses, incomes: [], period: month,
                                      usdToPen: ExchangeRateService.storedRate).spent
        updateBudgetNotice(spent: spent, month: month)

        let budgets = CategoryBudgetStore.shared.budgets.values.filter(\.hasLimit)
        let limitsEnabled = defaults.object(forKey: NotificationManager.categoryLimitEnabledKey) as? Bool ?? true
        guard !budgets.isEmpty else { return }

        // El ciclo actual y el anterior (por el sobrante) caben de sobra en
        // dos años, aunque el límite sea anual.
        let since = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? .distantPast
        let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.date >= since })
        let snapshots = ((try? context.fetch(descriptor)) ?? []).map(\.accountingSnapshot)
        let rate = ExchangeRateService.storedRate
        let statuses = budgets.map { budget in
            CategoryLimits.status(category: budget.category, budget: budget,
                                  expenses: snapshots, on: Date(), usdToPen: rate)
        }
        updateCategoryLimitNotices(statuses, enabled: limitsEnabled)
    }
    
    static let debtReminderID = "dailyDebtReminder"
    static let recurringReminderID = "recurringPendingReminder"

    func updateDebtNotification(hasDebts: Bool) {
        let center = UNUserNotificationCenter.current()
        // Sólo el suyo: `removeAllPendingNotificationRequests` borraba también
        // el recordatorio de recurrentes.
        center.removePendingNotificationRequests(withIdentifiers: [NotificationManager.debtReminderID])

        // El interruptor de Ajustes se respeta aquí y no en cada llamador:
        // varios lo ignoraban y volvían a programar el aviso ya apagado.
        let enabled = UserDefaults.standard.object(forKey: NotificationSettings.debtEnabledKey) as? Bool ?? true
        if hasDebts && enabled {
            let content = UNMutableNotificationContent()
            content.title = "Tienes cobros pendientes"
            content.body = "Hay dinero que aún no te devuelven. ¡Revisa tu resumen!"
            content.sound = .default
            
            // Hora y minuto, no una fecha completa: antes se guardaba un
            // `timeIntervalSince1970` y el recordatorio quedaba anclado al día
            // en que se configuró.
            var dateComponents = DateComponents()
            dateComponents.hour = NotificationSettings.hour()
            dateComponents.minute = NotificationSettings.minute()
            let date = NotificationSettings.date(hour: NotificationSettings.hour(),
                                                 minute: NotificationSettings.minute())
            
            let frequency = UserDefaults.standard.string(forKey: "debtNotificationFrequency") ?? "Diario"
            if frequency == "Semanal" {
                dateComponents.weekday = Calendar.current.component(.weekday, from: date)
            } else if frequency == "Mensual" {
                dateComponents.day = Calendar.current.component(.day, from: date)
            }
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: NotificationManager.debtReminderID, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error programando notificación de deuda: \(error.localizedDescription)")
                } else {
                    print("Notificación de deuda programada para: \(dateComponents) (\(frequency))")
                }
            }
        } else {
            print("No hay deudas. Notificaciones canceladas.")
        }
    }

    // MARK: - Presupuesto del mes

    private static let budgetNoticeID = "monthlyBudgetNotice"
    private static let budgetStateKey = "budgetNoticeState"

    /// Hasta dónde llegó el mes, de menos a más grave. Se avisa sólo al
    /// **subir** de nivel, una vez por mes: pasar del ritmo y después del 80%
    /// son dos avisos; registrar diez gastos más ya en el 80% no es ninguno.
    enum BudgetNoticeLevel: Int {
        case none = 0, overPace, near, over
    }

    /// Umbral del aviso "cerca", el mismo que promete Ajustes.
    static let budgetNearFraction = 0.8
    /// El ritmo sólo se juzga pasados unos días: el día 1 cualquier gasto ya
    /// va "por encima" de lo esperado, y avisar de eso es ruido.
    static let paceMinimumDays = 5
    /// Holgura sobre lo esperado antes de llamarlo "por encima del ritmo".
    static let paceTolerance = 1.1

    static func budgetLevel(for pace: Pace) -> BudgetNoticeLevel {
        if Money.cents(pace.spent) > Money.cents(pace.target) { return .over }
        if pace.usedFraction >= budgetNearFraction { return .near }
        if pace.period.elapsedDays >= paceMinimumDays,
           Money.cents(pace.spent) > Money.cents(Money.multiply(pace.expectedSpent, by: paceTolerance)) {
            return .overPace
        }
        return .none
    }

    func updateBudgetNotice(spent: Double, month: Period, defaults: UserDefaults = .standard) {
        let enabled = defaults.object(forKey: NotificationSettings.budgetKey) as? Bool ?? true
        let budgetEnabled = defaults.object(forKey: BudgetStore.enabledKey) as? Bool ?? true
        let monthlyBudget = defaults.double(forKey: BudgetStore.monthlyBudgetKey)

        guard enabled,
              let pace = BudgetStore.pace(monthlyBudget: monthlyBudget, enabled: budgetEnabled,
                                          for: month, spent: spent) else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [NotificationManager.budgetNoticeID])
            return
        }

        // Marca = inicio del mes + nivel más alto ya avisado. Un mes nuevo
        // arranca de cero; si un gasto se borra y el nivel baja, no se
        // vuelve a avisar del mismo nivel dentro del mes.
        let monthStamp = String(Int(month.interval.start.timeIntervalSince1970))
        let saved = (defaults.string(forKey: NotificationManager.budgetStateKey) ?? "").split(separator: "|")
        let notified = saved.count == 2 && saved[0] == monthStamp ? Int(saved[1]) ?? 0 : 0

        let level = NotificationManager.budgetLevel(for: pace)
        guard level.rawValue > notified else { return }
        defaults.set(monthStamp + "|" + String(level.rawValue), forKey: NotificationManager.budgetStateKey)

        let content = UNMutableNotificationContent()
        switch level {
        case .over:
            content.title = "Pasaste tu presupuesto del mes"
            content.body = "Llevas " + Money.format(pace.spent) + " de " + Money.format(pace.target)
                + ": " + Money.format(Money.subtract(pace.spent, pace.target)) + " arriba."
        case .near:
            content.title = "Llevas el \(pace.usedPercent)% de tu presupuesto"
            // `remainingDays` no cuenta hoy: el último día del mes vale 0.
            let days = pace.period.remainingDays + 1
            content.body = "Te quedan " + Money.format(pace.remaining) + " para "
                + (days == 1 ? "hoy, el último día del mes." : "los \(days) días que quedan del mes.")
        case .overPace:
            content.title = "Vas por encima de tu ritmo"
            content.body = pace.message
        case .none:
            return
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: NotificationManager.budgetNoticeID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Diagnostics.shared.log("Notificaciones: error en aviso de presupuesto: \(error.localizedDescription)") }
        }
    }

    // MARK: - Límites por categoría

    static let categoryLimitEnabledKey = "categoryLimitAlerts"
    private static let categoryLimitStateKey = "categoryLimitNoticeState"
    private static func categoryLimitID(_ category: String) -> String { "categoryLimit-" + category }

    /// Aviso del límite de una categoría.
    ///
    /// El color de la lista ya cuenta la historia cuando la app está abierta;
    /// esto es para cuando no lo está. Se manda **una vez por ciclo y por
    /// estado**: al cruzar el umbral y al pasarse. Repetirlo cada vez que se
    /// registra un gasto convertiría el aviso en ruido, y un aviso que se
    /// ignora es peor que ninguno.
    func updateCategoryLimitNotices(_ statuses: [CategoryLimitStatus],
                                    enabled: Bool,
                                    defaults: UserDefaults = .standard) {
        let center = UNUserNotificationCenter.current()

        guard enabled else {
            let ids = statuses.map { NotificationManager.categoryLimitID($0.category) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            defaults.removeObject(forKey: NotificationManager.categoryLimitStateKey)
            return
        }

        var state = defaults.dictionary(forKey: NotificationManager.categoryLimitStateKey) as? [String: String] ?? [:]

        for status in statuses where status.hasLimit {
            let level = status.level
            guard level == .cerca || level == .pasado else {
                state[status.category] = nil
                continue
            }

            // La marca lleva el inicio del ciclo: el mes siguiente vuelve a
            // avisar aunque el estado sea el mismo.
            let stamp = String(Int(status.cycleStart.timeIntervalSince1970)) + "|" + (level == .pasado ? "pasado" : "cerca")
            guard state[status.category] != stamp else { continue }
            state[status.category] = stamp

            let content = UNMutableNotificationContent()
            if level == .pasado {
                content.title = status.category + " pasó su límite"
                content.body = Money.formatCompact(status.overBy) + " arriba de "
                    + Money.formatCompact(status.limit) + ". El límite avisa, no bloquea: puedes seguir registrando."
            } else {
                content.title = status.category + " va por " + Money.formatPercent(status.spent, of: status.limit)
                content.body = "Quedan " + Money.formatCompact(status.remaining)
                    + " para el resto del ciclo (" + status.daysLeftLabel + ")."
            }
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: NotificationManager.categoryLimitID(status.category),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            )
            center.add(request) { error in
                if let error { print("Error programando aviso de límite: \(error.localizedDescription)") }
            }
        }

        defaults.set(state, forKey: NotificationManager.categoryLimitStateKey)
    }

    /// Recordatorio de gastos recurrentes vencidos.
    ///
    /// Sin esto las pendientes se acumulan sin que nadie las vea, y el mes se ve
    /// más barato de lo que es: no cuentan en ningún total hasta confirmarlas.
    func updateRecurringReminder(count: Int, total: Double, merchant: String?, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NotificationManager.recurringReminderID])
        guard enabled, count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Gastos programados para hoy"
        if count == 1, let merchant {
            content.body = merchant + " " + Money.format(total)
                + " programado para hoy. Confirma o ajusta el monto."
        } else {
            content.body = "\(count) gastos por " + Money.format(total)
                + " esperan tu confirmación. No cuentan en tu mes hasta que los aceptes."
        }
        content.sound = .default

        // A media mañana del mismo día; si ya pasó la hora, en un minuto.
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 10
        comps.minute = 0
        let fireDate = cal.date(from: comps) ?? Date()
        let interval = max(60, fireDate.timeIntervalSinceNow)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationManager.recurringReminderID,
                                            content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("Error programando recordatorio de recurrentes: \(error.localizedDescription)") }
        }
    }
}
