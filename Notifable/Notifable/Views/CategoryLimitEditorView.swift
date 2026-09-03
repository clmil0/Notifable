import SwiftUI

/// `6c` — Editar el límite.
///
/// Tres decisiones viven aquí: cuánto, cada cuánto se reinicia, y qué meses son
/// la excepción. El histórico está debajo del monto porque un límite se elige
/// mirando lo que de verdad gastas: por debajo del promedio se incumple siempre
/// y enseña a ignorar los avisos.
struct CategoryLimitEditorView: View {

    let category: String
    let color: Color
    let budget: CategoryBudget
    let history: [Expense]
    var onSave: (CategoryBudget) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    @AppStorage("period") private var period = Period()

    @StateObject private var rates = ExchangeRateService.shared

    /// Se edita una **copia**: "Cancelar" la descarta sin haber tocado el store.
    @State private var draft = CategoryBudget(category: "", amount: 0)
    @State private var amountText = ""
    @State private var showingAnchor = false
    @State private var showingOverride = false
    @State private var loaded = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        amountBlock
                        historyCard
                        cycleSection
                        overridesSection
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                }

                Keypad(background: palette.surfaceElevated,
                       onKey: press,
                       onClear: { amountText = "" })
            }
            .background(palette.background)
            .navigationTitle("Límite de " + category)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                }
            }
            .sheet(isPresented: $showingAnchor) { anchorPicker }
            .sheet(isPresented: $showingOverride) { overrideEditor }
            .appAppearance()
            .appTextSize()
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear(perform: load)
    }

    // MARK: - Carga y estado

    private func load() {
        guard !loaded else { return }
        loaded = true
        draft = budget
        draft.category = category
        amountText = budget.hasLimit ? trimmed(budget.amount) : ""
    }

    private func trimmed(_ value: Double) -> String {
        let cents = Money.cents(value)
        if cents % 100 == 0 { return String(cents / 100) }
        return String(format: "%.2f", Money.value(cents))
    }

    private var amount: Double { Money.normalized(Double(amountText) ?? 0) }

    private var referenceDate: Date { CategoryLimits.referenceDate(for: period) }
    private var snapshots: [ExpenseSnapshot] { history.map(\.accountingSnapshot) }

    private var cycles: [(interval: DateInterval, total: Double)] {
        CategoryLimits.history(budget: draft,
                               expenses: snapshots,
                               on: referenceDate,
                               closedCycles: 3,
                               usdToPen: rates.usdToPenRate)
    }

    private var average: Double? {
        CategoryLimits.average(budget: draft,
                               expenses: snapshots,
                               on: referenceDate,
                               usdToPen: rates.usdToPenRate)
    }

    private func press(_ key: TransactionDraft.KeypadKey) {
        switch key {
        case .digit(let d):
            if let dot = amountText.firstIndex(of: ".") {
                let decimals = amountText.distance(from: dot, to: amountText.endIndex) - 1
                guard decimals < 2 else { return }
            }
            guard amountText.replacingOccurrences(of: ".", with: "").count < 9 else { return }
            if amountText == "0" { amountText = String(d) } else { amountText.append(String(d)) }
        case .decimal:
            guard !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        case .backspace:
            guard !amountText.isEmpty else { return }
            amountText.removeLast()
        }
    }

    // MARK: - Monto

    private var amountBlock: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("S/")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryLabel)
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: 62, weight: .bold, design: .rounded))
                    .foregroundStyle(amountText.isEmpty ? palette.tertiaryLabel : palette.label)
                Rectangle()
                    .fill(color)
                    .frame(width: 3, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(maxWidth: .infinity)

            presets
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(roundPresets, id: \.self) { value in
                Button { amountText = String(Int(value)) } label: {
                    presetLabel(Money.formatCompact(value), highlighted: false)
                }
                .buttonStyle(.plain)
            }

            if let average {
                Button { amountText = String(Int(CategoryLimits.suggestedLimit(from: average))) } label: {
                    presetLabel("Promedio " + Money.formatCompact(average), highlighted: true)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func presetLabel(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.subheadline.weight(highlighted ? .semibold : .medium))
            .foregroundStyle(highlighted ? color : palette.label)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(highlighted ? color.opacity(0.18) : palette.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(highlighted ? color : palette.hairline, lineWidth: 0.5)
            )
    }

    /// Dos valores redondos cerca del actual. Con el campo vacío, dos valores
    /// alrededor del promedio; sin promedio, dos arranques razonables.
    private var roundPresets: [Double] {
        let base = Money.cents(amount) > 0 ? amount : (average ?? 300)
        let step: Double = base >= 1000 ? 100 : 50
        let anchor = (base / step).rounded() * step
        let lower = max(step, anchor - step)
        let upper = anchor + step
        return lower == upper ? [lower] : [lower, upper]
    }

    // MARK: - Histórico

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            LimitHistoryChart(cycles: cycles, limit: amount, color: color)
            Text(historyLegend)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    /// El texto se genera: cuenta cuántos ciclos quedan por debajo del límite.
    private var historyLegend: String {
        guard Money.cents(amount) > 0 else {
            return "Escribe un monto y verás dónde queda la línea frente a lo que ya gastaste."
        }
        let list = cycles
        let below = list.filter { Money.cents($0.total) <= Money.cents(amount) }.count
        if below == list.count {
            return "La línea del límite queda por encima de los \(list.count) ciclos. Es holgado: puedes bajarlo."
        }
        if below == 0 {
            return "La línea queda por debajo de todos los ciclos. Con este monto te pasarías siempre."
        }
        return "La línea del límite queda por encima de \(below) de los \(list.count) ciclos. Es una meta alcanzable, no un recorte."
    }

    // MARK: - Ciclo

    private var cycleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("SE REINICIA CADA")

            Picker("Ciclo", selection: cycleBinding) {
                ForEach(CategoryBudget.Cycle.allCases, id: \.self) { cycle in
                    Text(cycle.label).tag(cycle)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if draft.cycle.usesAnchorDay {
                Button { showingAnchor = true } label: {
                    Text(anchorNote)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .padding(.horizontal, 32)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cycleBinding: Binding<CategoryBudget.Cycle> {
        Binding(get: { draft.cycle }, set: { draft.cycle = $0 })
    }

    private var anchorNote: String {
        "El corte sigue tu día de pago: \(draft.safeAnchorDay) de cada mes. Tócalo para cambiarlo."
    }

    private var anchorPicker: some View {
        NavigationStack {
            List(1...28, id: \.self) { day in
                Button {
                    draft.anchorDay = day
                    showingAnchor = false
                } label: {
                    HStack {
                        Text("Día \(day)")
                        Spacer()
                        if draft.safeAnchorDay == day {
                            Image(systemName: "checkmark")
                                .foregroundStyle(accent.onSurface(scheme))
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Día de corte")
            .navigationBarTitleDisplayMode(.inline)
            .appAppearance()
            .appTextSize()
        }
        .presentationDetents([.medium])
    }

    // MARK: - Excepciones

    private var overridesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("MESES CON OTRO LÍMITE")

            VStack(spacing: 0) {
                ForEach(sortedOverrides) { override in
                    overrideRow(override)
                    Rectangle()
                        .fill(palette.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 52)
                }

                Button { showingOverride = true } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.track)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(palette.label)
                            )
                        Text("Programar otro mes")
                            .foregroundStyle(accent.onSurface(scheme))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)

            if !draft.overrides.isEmpty {
                Text("Fuera de estos meses vuelve solo a " + Money.formatCompact(amount) + ".")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var sortedOverrides: [CategoryBudget.Override] {
        draft.overrides.sorted { $0.month < $1.month }
    }

    private func overrideRow(_ override: CategoryBudget.Override) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.softFill(scheme))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(accent.onSurface(scheme))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(CategoryLimitEditorView.monthName(override.month))
                    .foregroundStyle(palette.label)
                Text(override.repeatsYearly ? "Se repite cada año" : "Sólo \(override.year ?? 0)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer()

            Text(Money.formatCompact(override.amount))
                .font(.body.weight(.semibold))
                .foregroundStyle(accent.onSurface(scheme))

            Button { remove(override) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(palette.secondaryLabel)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func remove(_ override: CategoryBudget.Override) {
        draft.overrides.removeAll { $0.id == override.id }
    }

    private var overrideEditor: some View {
        OverrideEditor(defaultAmount: amount) { override in
            draft.overrides.removeAll { $0.month == override.month && $0.year == override.year }
            draft.overrides.append(override)
        }
    }

    static func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.year = 2000
        components.month = max(1, min(12, month))
        components.day = 1
        let date = Period.calendar.date(from: components) ?? Date()
        return Period.spanishMonthName(for: date)
    }

    // MARK: - Guardar

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, 32)
    }

    private func save() {
        var result = draft
        result.category = category
        result.amount = amount
        onSave(result)
        dismiss()
    }
}

// MARK: - Histórico

/// Cuatro barras —tres ciclos cerrados y el actual— con la línea del límite
/// superpuesta. Sin la línea, las barras no responden a la pregunta que se está
/// haciendo el usuario, que es si ese número es alcanzable.
struct LimitHistoryChart: View {

    let cycles: [(interval: DateInterval, total: Double)]
    let limit: Double
    let color: Color

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private let barsHeight: CGFloat = 64

    private var maxValue: Double {
        let highest = cycles.map(\.total).max() ?? 0
        return max(max(highest, limit), 1)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(cycles.enumerated()), id: \.offset) { index, cycle in
                    bar(cycle: cycle, isCurrent: index == cycles.count - 1)
                }
            }

            if Money.cents(limit) > 0 {
                Rectangle()
                    .fill(palette.label.opacity(0.5))
                    .frame(height: 1)
                    .offset(y: -(barsHeight * CGFloat(min(1, limit / maxValue))) - 14)
            }
        }
    }

    private func bar(cycle: (interval: DateInterval, total: Double), isCurrent: Bool) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isCurrent ? color : palette.track)
                .frame(height: max(3, barsHeight * CGFloat(cycle.total / maxValue)))
            Text(label(for: cycle.interval))
                .font(.system(size: 10))
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? color : palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
    }

    private func label(for interval: DateInterval) -> String {
        Period.spanishMonthName(for: interval.start, abbreviated: true).uppercased()
    }
}

// MARK: - Excepción de un mes

struct OverrideEditor: View {

    let defaultAmount: Double
    var onSave: (CategoryBudget.Override) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var month = Period.calendar.component(.month, from: Date())
    @State private var amountText = ""
    @State private var yearly = true

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mes", selection: $month) {
                    ForEach(1...12, id: \.self) { value in
                        Text(CategoryLimitEditorView.monthName(value)).tag(value)
                    }
                }

                HStack {
                    Text("Límite")
                    Spacer()
                    TextField(Money.formatCompact(defaultAmount), text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Se repite cada año", isOn: $yearly)
            }
            .navigationTitle("Otro mes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") { add() }
                        .disabled(Money.cents(Double(amountText) ?? 0) <= 0)
                }
            }
            .appAppearance()
            .appTextSize()
        }
        .presentationDetents([.medium])
    }

    private func add() {
        let value = Money.normalized(Double(amountText) ?? 0)
        guard Money.cents(value) > 0 else { return }
        let year = yearly ? nil : Period.calendar.component(.year, from: Date())
        onSave(CategoryBudget.Override(month: month, year: year, amount: value))
        dismiss()
    }
}
