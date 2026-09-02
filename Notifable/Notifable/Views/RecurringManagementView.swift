import SwiftUI
import SwiftData

/// Ajustes → Recurrentes y atajos.
struct RecurringManagementView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    @AppStorage(BudgetStore.monthlyBudgetKey) private var monthlyBudget: Double = 0
    @AppStorage(BudgetStore.enabledKey) private var budgetEnabled = true

    @Query(sort: \RecurringExpense.createdAt, order: .reverse) private var rules: [RecurringExpense]
    @Query(sort: \QuickExpense.sortIndex) private var quickExpenses: [QuickExpense]

    @StateObject private var exchangeRateService = ExchangeRateService.shared

    @State private var editingQuick: QuickExpense?
    @State private var showQuickEditor = false
    @State private var ruleToDelete: RecurringExpense?

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        List {
            commitmentSection
            rulesSection
            quickSection
        }
        .navigationTitle("Recurrentes y atajos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingQuick = nil
                    showQuickEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuevo atajo")
            }
        }
        .sheet(isPresented: $showQuickEditor) {
            QuickExpenseEditor(quick: editingQuick)
        }
        .confirmationDialog("¿Eliminar esta programación?",
                            isPresented: deleteDialogBinding,
                            titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let rule = ruleToDelete { modelContext.delete(rule) }
                try? modelContext.save()
                ruleToDelete = nil
            }
            Button("Cancelar", role: .cancel) { ruleToDelete = nil }
        } message: {
            Text("Se eliminará la programación. Los gastos ya registrados se conservan.")
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { ruleToDelete != nil }, set: { if !$0 { ruleToDelete = nil } })
    }

    // MARK: - Compromiso mensual

    private var committed: Double {
        RecurringEngine.monthlyCommitted(rules: rules, usdToPen: exchangeRateService.usdToPenRate)
    }

    @ViewBuilder
    private var commitmentSection: some View {
        if !Money.isZero(committed) {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("COMPROMETIDO CADA MES")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)

                    Text(Money.format(committed))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    categoryBar

                    if let share = budgetShare {
                        Text(share)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    /// Barra segmentada por categoría: de dónde sale ese compromiso.
    private var categoryBar: some View {
        let segments = commitmentByCategory
        let total = Money.cents(committed)

        return GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments, id: \.category) { segment in
                    let fraction = total > 0 ? Double(Money.cents(segment.amount)) / Double(total) : 0
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CategoryStyle.color(for: segment.category, accent: accent.color))
                        .frame(width: max(2, geo.size.width * CGFloat(fraction)))
                }
            }
        }
        .frame(height: 8)
    }

    private var commitmentByCategory: [(category: String, amount: Double)] {
        var cents: [String: Int] = [:]
        for rule in rules where !rule.isPaused {
            cents[rule.category, default: 0] += Money.cents(rule.monthlyEquivalent)
        }
        return cents
            .map { (category: $0.key, amount: Money.value($0.value)) }
            .sorted { Money.cents($0.amount) > Money.cents($1.amount) }
    }

    /// Sin presupuesto no se inventa el porcentaje.
    private var budgetShare: String? {
        guard BudgetStore.hasBudget(monthlyBudget: monthlyBudget, enabled: budgetEnabled),
              let percent = Money.percent(committed, of: monthlyBudget) else { return nil }
        return "\(Int(percent.rounded()))% de tu presupuesto de "
            + Money.format(monthlyBudget) + " ya está comprometido antes de empezar el mes."
    }

    // MARK: - Reglas

    /// Las pausadas al final: siguen existiendo, pero no proponen nada.
    private var sortedRules: [RecurringExpense] {
        rules.sorted { lhs, rhs in
            if lhs.isPaused != rhs.isPaused { return !lhs.isPaused }
            return (lhs.nextOccurrence ?? .distantFuture) < (rhs.nextOccurrence ?? .distantFuture)
        }
    }

    @ViewBuilder
    private var rulesSection: some View {
        Section("Activos") {
            if rules.isEmpty {
                Text("Nada programado todavía. Al crear un gasto, usa «Repetir».")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                ForEach(sortedRules) { rule in
                    ruleRow(rule)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { ruleToDelete = rule } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                            Button { togglePause(rule) } label: {
                                Label(rule.isPaused ? "Reanudar" : "Pausar",
                                      systemImage: rule.isPaused ? "play.fill" : "pause.fill")
                            }
                            .tint(.orange)
                        }
                }
            }
        }
    }

    private func ruleRow(_ rule: RecurringExpense) -> some View {
        HStack(spacing: 12) {
            ruleIcon(rule)

            VStack(alignment: .leading, spacing: 2) {
                Text(Accounting.displayName(rule.merchant))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                Text(ruleSubtitle(rule))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Money.format(rule.amount, currency: rule.currency))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.label)
        }
        .opacity(rule.isPaused ? 0.5 : 1)
    }

    private func ruleIcon(_ rule: RecurringExpense) -> some View {
        let color = CategoryStyle.color(for: rule.category, accent: accent.color)
        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(color.opacity(0.2))
                .frame(width: 38, height: 38)
            Image(systemName: rule.isPaused ? "pause.fill" : CategoryStyle.icon(for: rule.category))
                .foregroundStyle(color)
        }
    }

    private func ruleSubtitle(_ rule: RecurringExpense) -> String {
        if rule.isPaused { return "Pausado · no propone nada" }
        var parts = [rule.scheduleLabel]
        if rule.autoConfirm {
            parts.append("automático")
        } else if let next = rule.nextOccurrence {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_PE")
            f.dateFormat = "d MMM"
            parts.append("próximo " + f.string(from: next))
        }
        return parts.joined(separator: " · ")
    }

    private func togglePause(_ rule: RecurringExpense) {
        withAnimation {
            rule.isPaused.toggle()
            try? modelContext.save()
        }
    }

    // MARK: - Atajos

    @ViewBuilder
    private var quickSection: some View {
        Section {
            if quickExpenses.isEmpty {
                Text("Ningún atajo todavía.")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                ForEach(quickExpenses) { quick in
                    Button {
                        editingQuick = quick
                        showQuickEditor = true
                    } label: {
                        quickRow(quick)
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: deleteQuick)
            }
        } header: {
            Text("Atajos")
        } footer: {
            Text("Los tres primeros aparecen en el modal de gasto. Toca uno para editar su monto o categoría.")
        }
    }

    private func quickRow(_ quick: QuickExpense) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CategoryStyle.color(for: quick.category, accent: accent.color).opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: quick.iconName)
                    .font(.footnote)
                    .foregroundStyle(CategoryStyle.color(for: quick.category, accent: accent.color))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(quick.label)
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                // El contador está a la vista a propósito: es lo que dice cuáles
                // vale la pena tener arriba.
                Text(quick.category + " · usado \(quick.useCount) " + (quick.useCount == 1 ? "vez" : "veces"))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Money.format(quick.amount, currency: quick.currency))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.label)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = quickExpenses
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, quick) in ordered.enumerated() { quick.sortIndex = index }
        try? modelContext.save()
    }

    private func deleteQuick(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(quickExpenses[index]) }
        try? modelContext.save()
    }
}
