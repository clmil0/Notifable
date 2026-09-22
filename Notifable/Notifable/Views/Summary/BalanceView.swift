import SwiftUI
import SwiftData

/// Balance (`2b`, `3b`, `3c`): el mes en números fríos.
///
/// **Sin entrada desde el dashboard único** (`1b`), por ahora: vuelve cuando
/// se rediseñe el presupuesto.
///
/// Sólo existe cuando hay un presupuesto definido (`3d`). Sin presupuesto, lo
/// único que tendría que decir —ingresos y cuánto queda— ya vive en la línea
/// secundaria de Hoy, y una pestaña entera para repetirlo sería relleno.
///
/// Aquí aterriza el desglose soles/dólares que se va del inicio: el titular de
/// Hoy enseña un total único convertido, y quien necesite ver qué parte era en
/// dólares lo encuentra en un solo sitio.
struct BalanceView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress
    /// Abre el formulario de ingreso desde la invitación de `3c`.
    var onAddIncome: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    @Query private var expenses: [Expense]
    @Query private var incomes: [Income]
    @StateObject private var rates = ExchangeRateService.shared

    @AppStorage(BudgetStore.monthlyBudgetKey) private var monthlyBudget = 0.0
    @AppStorage(BudgetStore.enabledKey) private var budgetEnabled = false

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }
    private var month: Period { Period(granularity: .mes, reference: Date()) }

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: incomes, period: month, usdToPen: rate)
    }

    private var pace: Pace? {
        BudgetStore.pace(monthlyBudget: monthlyBudget, enabled: budgetEnabled,
                         for: month, spent: totals.spent)
    }

    /// Suscripciones detectadas en el mes: lo que ya está comprometido pase lo
    /// que pase.
    private var subscriptions: [DetectedSubscription] {
        let calendar = Period.calendar
        let range = month.interval
        var grouped: [String: [Expense]] = [:]
        for expense in expenses
        where expense.isSubscription && expense.date >= range.start && expense.date < range.end {
            grouped[expense.merchant, default: []].append(expense)
        }
        return grouped.compactMap { merchant, items -> DetectedSubscription? in
            guard let last = items.max(by: { $0.date < $1.date }) else { return nil }
            return DetectedSubscription(merchant: merchant,
                                        amount: Accounting.amountInPEN(last, fallbackRate: rate),
                                        dayOfMonth: calendar.component(.day, from: last.date))
        }
        .sorted { Money.cents($0.amount) > Money.cents($1.amount) }
    }

    var body: some View {
        let totals = self.totals
        let pace = self.pace
        let hasIncome = !Money.isZero(totals.income)

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 18) {
                hero(totals: totals, pace: pace, hasIncome: hasIncome)

                if hasIncome {
                    HStack(spacing: 12) {
                        StatTile(label: "Ingresos",
                                 value: "+" + Money.format(totals.income),
                                 tint: accent.incomeColor(scheme))
                        StatTile(label: "Gastos",
                                 value: "–" + Money.format(totals.spent))
                    }
                }

                if let pace {
                    budgetCard(pace)

                    HStack(spacing: 12) {
                        StatTile(label: "Promedio diario", value: Money.format(pace.averagePerDay))
                        StatTile(label: "Disponible / día",
                                 value: pace.availablePerDay.map { Money.format($0) } ?? "—")
                    }
                }

                if !hasIncome {
                    noIncomeInvitation
                }

                if let currencies = currencyBreakdown(totals) {
                    currencyCard(currencies)
                }

                if !subscriptions.isEmpty {
                    subscriptionsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, ShellMetrics.contentTopInset)
            .padding(.bottom, ShellMetrics.contentBottomInset)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            progress.update(offset)
        }
    }

    // MARK: - Titular

    /// Con ingresos, «Queda en setiembre» es el balance real. Sin ellos no hay
    /// balance que dar, y el titular pasa a ser lo que queda del presupuesto:
    /// la única cifra honesta disponible (`3c`).
    @ViewBuilder
    private func hero(totals: PeriodTotals, pace: Pace?, hasIncome: Bool) -> some View {
        let amount = hasIncome ? (totals.balance ?? 0) : (pace?.remaining ?? 0)
        let caption = hasIncome
            ? "Queda en " + Period.spanishMonthName(for: Date()).lowercased()
            : "Queda del presupuesto"

        VStack(spacing: 6) {
            Text(caption.uppercased())
                .font(.system(size: 11.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(palette.secondaryLabel)

            Text((Money.cents(amount) < 0 ? "–" : "") + Money.format(abs(amount)))
                .font(.system(size: 44, weight: .bold))
                .tracking(-1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Money.cents(amount) < 0 ? palette.negative : palette.label)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    // MARK: - Presupuesto

    private func budgetCard(_ pace: Pace) -> some View {
        ShellCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Presupuesto del mes")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)

                    Spacer()

                    Text(Money.format(pace.spent) + " / " + Money.formatCompact(pace.target))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(palette.secondaryLabel)
                }

                PaceBar(fraction: pace.usedFraction,
                        expected: pace.expectedFraction,
                        status: pace.status)

                ShellNote(icon: paceIcon(pace.status),
                          text: "Vas al \(pace.usedPercent)% del presupuesto con el "
                              + "\(pace.expectedPercent)% del mes transcurrido.",
                          tint: paceTint(pace.status))
            }
        }
    }

    private func paceIcon(_ status: Pace.Status) -> String {
        switch status {
        case .ok:      return "checkmark.circle"
        case .warning: return "exclamationmark.circle"
        case .over:    return "exclamationmark.triangle"
        }
    }

    private func paceTint(_ status: Pace.Status) -> Color {
        switch status {
        case .ok:      return palette.secondaryLabel
        case .warning: return palette.warning
        case .over:    return palette.negative
        }
    }

    // MARK: - Sin ingresos

    private var noIncomeInvitation: some View {
        ShellCard {
            HStack(spacing: 12) {
                MovementIcon(icon: "arrow.down.left", color: accent.incomeFillColor, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sin ingresos este mes")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Text("Regístralos y verás cuánto te queda de verdad, no sólo del presupuesto.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Button(action: onAddIncome) {
                    Text("Añadir")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(accent.color, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Por moneda

    /// `nil` cuando todo el periodo está en soles, que es el caso normal en
    /// Perú: sin un solo movimiento en dólares la tarjeta no se dibuja, ni el
    /// tipo de cambio (`3b`).
    private func currencyBreakdown(_ totals: PeriodTotals) -> (soles: Double, dollars: Double)? {
        let dollars = totals.spentBag.amount(in: "USD")
        guard Money.cents(dollars) != 0 else { return nil }
        return (totals.spentBag.amount(in: "PEN"), dollars)
    }

    private func currencyCard(_ currencies: (soles: Double, dollars: Double)) -> some View {
        ShellCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Por moneda")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.label)

                HStack {
                    Text("Soles")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondaryLabel)
                    Spacer()
                    Text("–" + Money.format(currencies.soles))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)
                }

                Rectangle().fill(palette.separator).frame(height: 0.5)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dólares")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.secondaryLabel)
                        Text("· " + String(format: "%.2f", rate))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.tertiaryLabel)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("–" + Money.format(currencies.dollars, currency: "USD"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.label)
                        // La conversión siempre acompaña al monto en dólares:
                        // un importe suelto en otra moneda no se puede comparar
                        // con nada de lo que hay en el resto de la pantalla.
                        Text("= " + Money.format(Money.multiply(currencies.dollars, by: rate)))
                            .font(.system(size: 11.5))
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                }
            }
        }
    }

    // MARK: - Comprometido

    private var subscriptionsSection: some View {
        let total = Money.sum(subscriptions) { $0.amount }

        return VStack(spacing: 8) {
            ShellSectionHeader(title: "Comprometido cada mes", trailing: Money.format(total))

            MovementCard {
                ForEach(Array(subscriptions.enumerated()), id: \.element.id) { index, subscription in
                    HStack(spacing: 12) {
                        MovementIcon(icon: CategoryStyle.icon(for: subscription.merchant),
                                     color: accent.color)

                        Text(Accounting.displayName(subscription.merchant))
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(palette.label)
                            .lineLimit(1)

                        Text("· día \(subscription.dayOfMonth)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.secondaryLabel)

                        Spacer(minLength: 6)

                        Text(Money.format(subscription.amount))
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(palette.label)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if index < subscriptions.count - 1 { MovementSeparator() }
                }
            }
        }
    }
}
