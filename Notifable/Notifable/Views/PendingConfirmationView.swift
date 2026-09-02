import SwiftUI
import SwiftData

/// "Por confirmar": las ocurrencias vencidas de las reglas recurrentes.
///
/// Nada de esto existe como `Expense` todavía, así que **no cuenta en ningún
/// total**. Es deliberado: el número grande del Resumen sólo refleja gasto real,
/// y por eso la pantalla lo dice en voz alta — si no, el usuario cree que le
/// falta dinero.
struct PendingConfirmationView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("isDarkMode") private var isDarkMode = true
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    @Query private var rules: [RecurringExpense]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var undoStack: [Expense] = []
    @State private var showUndo = false
    @State private var expandedOccurrence: String?

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    private var occurrences: [PendingOccurrence] {
        RecurringEngine.pending(rules: rules, expenses: expenses)
    }

    private var awaiting: [PendingOccurrence] { occurrences.filter(\.isAwaiting) }

    private var awaitingTotal: Double {
        Money.sum(awaiting) { $0.totalAmount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if occurrences.isEmpty {
                        ContentUnavailableView("Nada por confirmar",
                                               systemImage: "checkmark.circle.fill",
                                               description: Text("Tus gastos programados están al día."))
                            .padding(.top, 40)
                    } else {
                        contextBanner

                        ForEach(occurrences) { occurrence in
                            card(for: occurrence)
                        }

                        explanationNote
                    }
                }
                .padding(.vertical, 16)
            }
            .background(palette.background)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("Por confirmar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .appTextSize()
        }
    }

    // MARK: - Banner

    private var contextBanner: some View {
        let count = awaiting.reduce(0) { $0 + $1.dates.count }

        return VStack(alignment: .leading, spacing: 4) {
            Text(count == 1 ? "1 gasto recurrente espera tu confirmación"
                            : "\(count) gastos recurrentes esperan tu confirmación")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.label)
            // La frase que evita que el usuario crea que le falta dinero.
            Text("No cuentan en tu mes hasta que los aceptes.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(palette.warning.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.warning.opacity(0.4), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Tarjetas

    @ViewBuilder
    private func card(for occurrence: PendingOccurrence) -> some View {
        switch occurrence.status {
        case .awaiting:
            awaitingCard(occurrence)
        case .satisfiedByBank(_, let bankAmount, let daysApart):
            bankCard(occurrence, bankAmount: bankAmount, daysApart: daysApart)
        }
    }

    private func awaitingCard(_ occurrence: PendingOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                icon(for: occurrence.category)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Accounting.displayName(occurrence.merchant))
                        .font(.headline)
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                    Text(scheduleText(occurrence))
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(Money.format(occurrence.totalAmount, currency: occurrence.currency))
                    .font(.title3.bold())
                    .foregroundStyle(palette.label)
            }

            if occurrence.dates.count > 1, expandedOccurrence == occurrence.id {
                ForEach(occurrence.dates, id: \.self) { date in
                    HStack {
                        Text(longDate(date))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                        Spacer()
                        Text(Money.format(occurrence.expectedAmount, currency: occurrence.currency))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }

            HStack(spacing: 8) {
                Button { confirm(occurrence) } label: {
                    Text(occurrence.dates.count > 1 ? "Confirmar los \(occurrence.dates.count)" : "Confirmar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(accent.color)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                if occurrence.dates.count > 1 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            expandedOccurrence = expandedOccurrence == occurrence.id ? nil : occurrence.id
                        }
                    } label: {
                        Text("Ver días")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.label)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(palette.track)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button { skip(occurrence) } label: {
                    Text("Omitir")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryLabel)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
            }
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

    /// Sin acciones: sólo informa de que la deduplicación hizo su trabajo.
    private func bankCard(_ occurrence: PendingOccurrence, bankAmount: Double, daysApart: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                icon(for: occurrence.category)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.positive)
                        Text(Accounting.displayName(occurrence.merchant))
                            .font(.headline)
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                    }
                    Text("Ya llegó del banco el " + shortDate(occurrence.dates.first ?? Date())
                         + " · no se duplicó")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(Money.format(bankAmount, currency: occurrence.currency))
                    .font(.title3.bold())
                    .foregroundStyle(palette.positive)
            }

            Text("La regla encontró el cobro real del banco a \(daysApart) "
                 + (daysApart == 1 ? "día" : "días")
                 + " de la fecha programada y se marcó cumplida. El monto que cuenta es el del banco.")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.positive.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .onAppear { acknowledge(occurrence) }
    }

    private func icon(for category: String) -> some View {
        let color = CategoryStyle.color(for: category, accent: accent.color)
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.2))
                .frame(width: 40, height: 40)
            Image(systemName: CategoryStyle.icon(for: category))
                .foregroundStyle(color)
        }
    }

    // MARK: - Pie

    private var explanationNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POR QUÉ NO SE REGISTRAN SOLOS")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
            Text("Insertar sin preguntar duplicaría el cobro que ya llegó por correo, o inflaría el mes con un gasto que no ocurrió — el gimnasio que dejaste de pagar. Puedes activarlo por regla si el monto nunca cambia.")
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bottomBar: some View {
        if showUndo {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.positive)
                Text(undoStack.count == 1 ? "1 gasto registrado" : "\(undoStack.count) gastos registrados")
                    .font(.subheadline)
                    .foregroundStyle(palette.label)
                Spacer()
                Button("Deshacer") { undo() }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent.onSurface(scheme))
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(16)
        } else if !awaiting.isEmpty {
            Button { confirmAll() } label: {
                Text("Confirmar todo — " + Money.format(awaitingTotal))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accent.color)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(16)
            .background(palette.background)
        }
    }

    // MARK: - Acciones

    private func rule(for occurrence: PendingOccurrence) -> RecurringExpense? {
        rules.first { $0.id == occurrence.ruleID }
    }

    private func confirm(_ occurrence: PendingOccurrence, override: Double? = nil) {
        guard let rule = rule(for: occurrence) else { return }
        let created = RecurringEngine.confirm(occurrence, rule: rule, amountOverride: override, in: modelContext)
        try? modelContext.save()
        offerUndo(created)
    }

    private func confirmAll() {
        var created: [Expense] = []
        for occurrence in awaiting {
            guard let rule = rule(for: occurrence) else { continue }
            created += RecurringEngine.confirm(occurrence, rule: rule, in: modelContext)
        }
        try? modelContext.save()
        offerUndo(created)
    }

    private func skip(_ occurrence: PendingOccurrence) {
        guard let rule = rule(for: occurrence) else { return }
        withAnimation {
            RecurringEngine.skip(occurrence, rule: rule)
            try? modelContext.save()
        }
    }

    private func acknowledge(_ occurrence: PendingOccurrence) {
        guard let rule = rule(for: occurrence) else { return }
        RecurringEngine.acknowledgeBankMatch(occurrence, rule: rule)
        try? modelContext.save()
    }

    /// Cada confirmación es reversible durante unos segundos.
    private func offerUndo(_ created: [Expense]) {
        guard !created.isEmpty else { return }
        undoStack = created
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showUndo = true }

        let snapshot = created.map(\.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard undoStack.map(\.id) == snapshot else { return }
            withAnimation(.easeInOut) {
                showUndo = false
                undoStack = []
            }
        }
    }

    private func undo() {
        withAnimation {
            for expense in undoStack { modelContext.delete(expense) }
            try? modelContext.save()
            undoStack = []
            showUndo = false
        }
    }

    // MARK: - Texto

    private func scheduleText(_ occurrence: PendingOccurrence) -> String {
        guard let first = occurrence.dates.first else { return "" }
        if occurrence.dates.count == 1 {
            let cal = Period.calendar
            if cal.isDateInToday(first) { return "Programado para hoy, " + shortDate(first) }
            if cal.isDateInYesterday(first) { return "Programado para ayer, " + shortDate(first) }
            return "Programado para " + longDate(first)
        }
        let names = occurrence.dates.prefix(3).map { longDate($0) }
        return names.joined(separator: " y ")
    }

    private func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "EEEE d"
        return f.string(from: date).capitalizedFirst
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
