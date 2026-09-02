import SwiftUI
import SwiftData
import UIKit

/// Alta de gasto o ingreso. Reemplaza a `AddExpenseView`.
///
/// Tres cosas cambian de fondo respecto al modal anterior:
/// el monto —lo único que el usuario viene a escribir— deja de ser el elemento
/// más pequeño de la pantalla; el tipo se puede cambiar sin cerrar y volver a
/// abrir; y el botón nunca acepta un toque sin hacer nada: si falta algo, está
/// deshabilitado y su propio texto dice qué falta.
struct AddTransactionSheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue

    @Query(filter: #Predicate<Expense> { $0.isDebt == true }, sort: \Expense.date, order: .reverse)
    private var activeDebts: [Expense]
    @Query(sort: \Expense.date, order: .reverse) private var history: [Expense]
    @Query(sort: \QuickExpense.sortIndex) private var quickExpenses: [QuickExpense]

    @State private var draft: TransactionDraft
    @State private var showDatePicker = false
    @State private var showAllCategories = false
    @State private var showDebtPicker = false
    @State private var showDiscardDialog = false
    @State private var justSaved = false
    @State private var recurrence = RecurrenceDraft()
    @State private var showRecurrenceSheet = false
    @State private var showQuickEditor = false
    @State private var activeQuickID: UUID?
    @State private var saveAsQuick = false
    /// Gasto creado por doble toque, mientras el toast de deshacer sigue vivo.
    @State private var undoTarget: Expense?
    @State private var pendingDismissToken = UUID()
    @State private var editingQuick: QuickExpense?
    /// Mientras se escribe en un campo de texto el teclado del sistema ya ocupa
    /// media pantalla; el numérico propio sobra y tapaba el formulario.
    @FocusState private var textFieldFocused: Bool

    init(transactionType: TransactionType = .gasto) {
        _draft = State(initialValue: TransactionDraft(type: transactionType))
    }

    // MARK: - Colores

    private var palette: Palette { Palette(scheme) }
    private var themeAccent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }

    /// Verde de relleno para ingreso: `#30D158` no llega a 4.5:1 con texto blanco.
    private static let incomeFill = Color(red: 0.141, green: 0.541, blue: 0.239)   // #248A3D

    private var accentFill: Color {
        draft.type == .gasto ? themeAccent.color : Self.incomeFill
    }

    private var accentText: Color {
        draft.type == .gasto
            ? themeAccent.onSurface(scheme)
            : (scheme == .dark ? Color(red: 0.188, green: 0.820, blue: 0.345)
                               : Color(red: 0.114, green: 0.498, blue: 0.235))
    }

    private var keypadBackground: Color {
        scheme == .dark ? Color(red: 0.055, green: 0.055, blue: 0.063)   // #0E0E10
                        : Color(red: 0.949, green: 0.949, blue: 0.969)   // #F2F2F7
    }

    // MARK: - Cuerpo

    var body: some View {
        VStack(spacing: 0) {
            topBar
            amountHero

            ScrollView {
                VStack(spacing: 14) {
                    if draft.type == .gasto {
                        expenseFields
                    } else {
                        incomeFields
                    }
                }
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)

            if !textFieldFocused {
                Keypad(background: keypadBackground) { key in
                    withAnimation(.none) { draft.press(key) }
                } onClear: {
                    draft.amountText = ""
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            primaryButton
        }
        .background(palette.background)
        .animation(.easeInOut(duration: 0.2), value: textFieldFocused)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(palette.background)
        // Con datos escritos no se descarta de un arrastre; para salir hay que
        // usar Cancelar, que sí pregunta.
        .interactiveDismissDisabled(draft.hasAmount)
        .confirmationDialog("¿Descartar este movimiento?",
                            isPresented: $showDiscardDialog,
                            titleVisibility: .visible) {
            Button("Descartar movimiento", role: .destructive) { dismiss() }
            Button("Seguir editando", role: .cancel) {}
        }
        .sheet(isPresented: $showDatePicker) { datePickerSheet }
        .sheet(isPresented: $showAllCategories) { categoryListSheet }
        .sheet(isPresented: $showDebtPicker) { debtPickerSheet }
        .sheet(isPresented: $showRecurrenceSheet) {
            RecurrenceSheet(draft: $recurrence,
                            merchant: draft.merchant,
                            amount: draft.amount,
                            currency: draft.currency)
        }
        .sheet(isPresented: $showQuickEditor) {
            QuickExpenseEditor(quick: editingQuick)
        }
        .onAppear(perform: preselectSingleDebt)
    }

    // MARK: - 1. Barra superior

    /// Sólo "Cancelar". El tipo de movimiento se elige en los botones flotantes
    /// del `+` antes de abrir, así que un segmentado aquí repetía esa decisión y
    /// se comía la altura que el teclado necesita.
    private var topBar: some View {
        HStack {
            Button {
                if draft.hasAmount { showDiscardDialog = true } else { dismiss() }
            } label: {
                Text("Cancelar")
                    .font(.body)
                    .foregroundStyle(accentText)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    // MARK: - 2. Hero de monto

    private var amountHero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(amountLabel)
                    .font(.caption)
                    .tracking(0.3)
                    .foregroundStyle(palette.secondaryLabel)

                Spacer()

                currencyPicker
            }

            amountRow

            if case .invalid(let message) = draft.validation {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountLabel: String {
        if draft.type == .ingreso && draft.isDebtPayment { return "MONTO DEL ABONO" }
        return draft.type == .gasto ? "MONTO DEL GASTO" : "MONTO DEL INGRESO"
    }

    private var isInvalid: Bool {
        if case .invalid = draft.validation { return true }
        return false
    }

    private var amountRow: some View {
        let symbolColor: Color = isInvalid ? palette.negative
            : (draft.type == .ingreso ? accentText : palette.secondaryLabel)
        let amountColor: Color = isInvalid ? palette.negative
            : (draft.amountText.isEmpty ? palette.tertiaryLabel : palette.label)

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(symbolPrefix)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(symbolColor)

            Text(draft.displayAmount)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            BlinkingCursor(color: accentFill)

            Spacer(minLength: 0)
        }
        .frame(height: 60)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(amountLabel)
        .accessibilityValue(Money.format(draft.amount, currency: draft.currency))
    }

    private var symbolPrefix: String {
        let symbol = draft.currency == "USD" ? "US$" : "S/"
        return draft.type == .ingreso ? "+ " + symbol : symbol
    }

    /// Sólo hay dos monedas: un segmentado de 26 pt en vez del `Picker` de rueda
    /// de 80 pt que ocupaba el modal anterior.
    private var currencyPicker: some View {
        HStack(spacing: 0) {
            currencyOption("S/", value: "PEN")
            currencyOption("US$", value: "USD")
        }
        .padding(2)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func currencyOption(_ label: String, value: String) -> some View {
        let selected = draft.currency == value
        return Button {
            // No se convierte el monto: el número escrito es el de esa moneda.
            withAnimation(.easeInOut(duration: 0.15)) { draft.currency = value }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.white : palette.secondaryLabel)
                .frame(width: 44, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? accentFill : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 3a. Campos de gasto

    @ViewBuilder
    private var expenseFields: some View {
        // Lo primero que se ve: el caso de los S/ 2.50 de pasaje tiene que
        // resolverse sin bajar la vista.
        quickExpenseRow

        merchantField

        if !merchantSuggestions.isEmpty {
            chipRow {
                ForEach(merchantSuggestions, id: \.self) { name in
                    Button { pickMerchant(name) } label: {
                        chipLabel(Accounting.displayName(name), tint: palette.secondaryLabel, selected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        categoryChips
        dateAndSubscriptionCard
    }

    // MARK: - Atajos

    @ViewBuilder
    private var quickExpenseRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ATAJOS")
                    .font(.caption)
                    .tracking(0.3)
                    .foregroundStyle(palette.secondaryLabel)
                Spacer()
                if !quickExpenses.isEmpty {
                    Button("Editar") {
                        editingQuick = nil
                        showQuickEditor = true
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentText)
                }
            }
            .padding(.horizontal, 16)

            if quickExpenses.isEmpty {
                emptyQuickCard
            } else {
                chipRow {
                    ForEach(quickExpenses.prefix(3)) { quick in
                        quickCard(quick)
                    }
                    addQuickButton
                }
            }
        }
    }

    private func quickCard(_ quick: QuickExpense) -> some View {
        let active = activeQuickID == quick.id

        return VStack(alignment: .leading, spacing: 4) {
            quickIcon(quick)
            Text(quick.label)
                .font(.caption.bold())
                .foregroundStyle(palette.label)
                .lineLimit(1)
            Text(Money.format(quick.amount, currency: quick.currency))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(palette.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(width: 88, height: 62, alignment: .leading)
        .background(active ? accentFill.opacity(0.2) : palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? accentFill.opacity(0.6) : palette.hairline, lineWidth: active ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        // El orden importa: el doble toque debe reconocerse antes que el simple.
        .onTapGesture(count: 2) { saveImmediately(quick) }
        .onTapGesture { apply(quick) }
        .onLongPressGesture {
            editingQuick = quick
            showQuickEditor = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(quick.label + ", " + Money.format(quick.amount, currency: quick.currency))
        .accessibilityHint("Toca para rellenar, toca dos veces para guardar")
    }

    @ViewBuilder
    private func quickIcon(_ quick: QuickExpense) -> some View {
        if quick.iconName == "yape" || quick.iconName == "plin" {
            Image(quick.iconName + "_icon")
                .resizable()
                .scaledToFill()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: quick.iconName)
                .font(.system(size: 18))
                .foregroundStyle(accentText)
        }
    }

    private var addQuickButton: some View {
        Button {
            editingQuick = nil
            showQuickEditor = true
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
                .frame(width: 56, height: 62)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Añadir atajo")
    }

    private var emptyQuickCard: some View {
        Button {
            editingQuick = nil
            showQuickEditor = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Crea un atajo para lo que pagas en efectivo")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.leading)
                    Text("El pasaje de S/ 2.50 en un toque")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.label)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    /// Un toque: rellena y espera confirmación. Dos toques en total.
    private func apply(_ quick: QuickExpense) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            draft.amountText = String(format: "%.2f", quick.amount)
            draft.currency = quick.currency
            draft.merchant = quick.merchant
            draft.category = quick.category
            activeQuickID = quick.id
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Doble toque: el camino de un solo gesto para el pasaje diario.
    private func saveImmediately(_ quick: QuickExpense) {
        let expense = quick.makeExpense()
        modelContext.insert(expense)
        quick.useCount += 1
        quick.lastUsedAt = Date()
        try? modelContext.save()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        undoTarget = expense
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { justSaved = true }
        scheduleDismiss()
    }

    /// Se cierra sola a los 3 s, salvo que se deshaga antes.
    private func scheduleDismiss() {
        let token = UUID()
        pendingDismissToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard pendingDismissToken == token else { return }
            dismiss()
        }
    }

    private func undoQuickSave() {
        guard let expense = undoTarget else { return }
        pendingDismissToken = UUID()          // cancela el cierre programado
        modelContext.delete(expense)
        try? modelContext.save()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            undoTarget = nil
            justSaved = false
        }
    }

    private var merchantField: some View {
        HStack(spacing: 10) {
            Image(systemName: "bag")
                .font(.system(size: 19))
                .foregroundStyle(palette.secondaryLabel)

            TextField("Comercio", text: $draft.merchant)
                .font(.body)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .focused($textFieldFocused)
                .onSubmit { textFieldFocused = false }

            if !draft.merchant.isEmpty {
                Button { draft.merchant = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.secondaryLabel)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    /// Los comercios más frecuentes. Tocar uno llena el campo y preselecciona la
    /// categoría que ese comercio ya tiene: el atajo que hace innecesario escribir.
    private var merchantSuggestions: [String] {
        var counts: [String: Int] = [:]
        for expense in history where !expense.merchant.isEmpty {
            counts[expense.merchant, default: 0] += 1
        }
        let typed = draft.merchant.trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                                   locale: Locale(identifier: "es_PE"))
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
            .filter { name in
                guard !typed.isEmpty else { return true }
                let clean = Accounting.displayName(name)
                    .folding(options: [.diacriticInsensitive, .caseInsensitive],
                             locale: Locale(identifier: "es_PE"))
                return clean.contains(typed) && clean != typed
            }
            .prefix(4)
            .map { $0 }
    }

    private func pickMerchant(_ name: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            draft.merchant = Accounting.displayName(name)
            if let usual = usualCategory(for: name) { draft.category = usual }
        }
    }

    private func usualCategory(for merchant: String) -> String? {
        if let rule = MerchantRules.category(for: merchant) { return rule }
        var counts: [String: Int] = [:]
        for expense in history where expense.merchant == merchant && expense.category != Accounting.unclassified {
            counts[expense.category, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CATEGORÍA")
                .font(.caption)
                .tracking(0.3)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 16)

            chipRow {
                ForEach(selectableCategories.prefix(6), id: \.self) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { draft.category = category }
                    } label: {
                        categoryChip(category)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.category == category ? [.isSelected] : [])
                }

                Button { showAllCategories = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                        .frame(width: 38, height: 34)
                        .background(palette.surface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Más categorías")
            }
        }
    }

    private var selectableCategories: [String] {
        CategoryStyle.selectable(history: history)
    }

    private func categoryChip(_ category: String) -> some View {
        let color = CategoryStyle.color(for: category, accent: themeAccent.color)
        let selected = draft.category == category

        return HStack(spacing: 6) {
            Image(systemName: CategoryStyle.icon(for: category))
                .font(.caption)
            Text(category)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(selected ? color : palette.secondaryLabel)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(selected ? color.opacity(0.2) : palette.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(selected ? color.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }

    private var dateAndSubscriptionCard: some View {
        VStack(spacing: 0) {
            dateRow
            Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 14)
            repeatRow

            if canSaveAsQuick {
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 14)
                saveAsQuickRow
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    /// **Campo nuevo:** el gasto no tenía fecha, siempre se guardaba con `Date()`.
    /// Registrar el almuerzo de ayer era imposible.
    private var dateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 17))
                .foregroundStyle(palette.secondaryLabel)
            Text("Fecha")
                .foregroundStyle(palette.label)

            Spacer()

            HStack(spacing: 6) {
                dateChip("Hoy", isActive: isSameDay(draft.date, Date())) {
                    draft.date = Date()
                }
                dateChip("Ayer", isActive: isSameDay(draft.date, yesterday)) {
                    draft.date = yesterday
                }
                dateChip(otherDateLabel, isActive: isOtherDate) {
                    showDatePicker = true
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }

    private var yesterday: Date {
        Period.calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Period.calendar.isDate(a, inSameDayAs: b)
    }

    private var isOtherDate: Bool {
        !isSameDay(draft.date, Date()) && !isSameDay(draft.date, yesterday)
    }

    private var otherDateLabel: String {
        guard isOtherDate else { return "Otra" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        return f.string(from: draft.date)
    }

    private func dateChip(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? Color.white : palette.secondaryLabel)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(isActive ? accentFill : palette.track)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    /// El toggle "Es suscripción" desaparece: sólo ponía una marca en un gasto
    /// suelto, sin programar nada ni saber cuándo tocaba el siguiente.
    /// `isSubscription` pasa a derivarse de `frequency != .never`.
    private var repeatRow: some View {
        Button { showRecurrenceSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17))
                    .foregroundStyle(palette.secondaryLabel)
                Text("Repetir")
                    .foregroundStyle(palette.label)

                Spacer()

                Text(recurrence.label(merchant: draft.merchant, amount: draft.amount, currency: draft.currency))
                    .foregroundStyle(recurrence.repeats ? accentText : palette.secondaryLabel)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Sólo aparece cuando hay algo que guardar y no existe ya el mismo atajo.
    private var canSaveAsQuick: Bool {
        guard draft.hasAmount, !draft.merchant.trimmed.isEmpty else { return false }
        let cents = Money.cents(draft.amount)
        return !quickExpenses.contains {
            $0.merchant.caseInsensitiveCompare(draft.merchant.trimmed) == .orderedSame
                && Money.cents($0.amount) == cents
        }
    }

    private var saveAsQuickRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 17))
                .foregroundStyle(palette.secondaryLabel)

            VStack(alignment: .leading, spacing: 1) {
                Text("Guardar como atajo")
                    .foregroundStyle(palette.label)
                Text("Un toque la próxima vez")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer()

            Toggle("", isOn: $saveAsQuick)
                .labelsHidden()
                .tint(accentFill)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    // MARK: - 3b. Campos de ingreso

    @ViewBuilder
    private var incomeFields: some View {
        sourceChips
        titleAndDateCard

        if !activeDebts.isEmpty {
            debtToggle
        }

        if draft.isDebtPayment {
            debtCard
        } else {
            explanationNote
        }
    }

    private var sourceChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ORIGEN")
                .font(.caption)
                .tracking(0.3)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 16)

            chipRow {
                ForEach(Self.sources, id: \.name) { source in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { draft.source = source.name }
                    } label: {
                        sourceChip(source)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.source == source.name ? [.isSelected] : [])
                }
            }
        }
    }

    private struct SourceOption {
        let name: String
        let symbol: String?
        let asset: String?
    }

    private static let sources: [SourceOption] = [
        SourceOption(name: "Transferencia", symbol: "building.columns", asset: nil),
        SourceOption(name: "Yape", symbol: nil, asset: "yape_icon"),
        SourceOption(name: "Plin", symbol: nil, asset: "plin_icon"),
        SourceOption(name: "Efectivo", symbol: "banknote", asset: nil),
        SourceOption(name: "Otro", symbol: "ellipsis.circle", asset: nil)
    ]

    private func sourceChip(_ source: SourceOption) -> some View {
        let selected = draft.source == source.name

        return HStack(spacing: 6) {
            if let asset = source.asset {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else if let symbol = source.symbol {
                Image(systemName: symbol)
                    .font(.caption)
            }
            Text(source.name)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(selected ? accentText : palette.secondaryLabel)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(selected ? accentFill.opacity(0.2) : palette.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(selected ? accentFill.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }

    private var titleAndDateCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 17))
                    .foregroundStyle(palette.secondaryLabel)

                TextField("Título", text: $draft.title)
                    .font(.body)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($textFieldFocused)
                    .onSubmit { textFieldFocused = false }

                // "Opcional" a la derecha en vez de dentro del placeholder: así
                // no desaparece en cuanto empiezas a escribir.
                if draft.title.isEmpty {
                    Text("Opcional")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)

            Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 14)

            dateRow
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var debtToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 17))
                .foregroundStyle(palette.warning)

            VStack(alignment: .leading, spacing: 1) {
                Text("¿Es abono a una deuda?")
                    .foregroundStyle(palette.label)
                Text(activeDebts.count == 1 ? "Tienes 1 deuda activa" : "Tienes \(activeDebts.count) deudas activas")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer()

            Toggle("", isOn: debtToggleBinding)
                .labelsHidden()
                .tint(accentFill)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var debtToggleBinding: Binding<Bool> {
        Binding(
            get: { draft.isDebtPayment },
            set: { on in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    draft.isDebtPayment = on
                    if on { preselectSingleDebt() } else { draft.selectedDebt = nil }
                }
            }
        )
    }

    private func preselectSingleDebt() {
        guard draft.isDebtPayment, draft.selectedDebt == nil, activeDebts.count == 1 else { return }
        draft.selectedDebt = activeDebts.first
    }

    /// La distinción que ACCOUNTING.md §3 y §4 exigen y que ninguna pantalla
    /// explicaba: por qué un abono no aparece en el balance.
    private var explanationNote: some View {
        Text("Un ingreso normal cuenta en tu balance. Un abono a deuda no: sólo reduce lo que debes.")
            .font(.footnote)
            .foregroundStyle(palette.secondaryLabel)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
    }

    // MARK: - 3c. Tarjeta de abono a deuda

    @ViewBuilder
    private var debtCard: some View {
        VStack(spacing: 0) {
            debtChooserRow

            if draft.selectedDebt != nil {
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 14)
                balanceRow
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 14)
                debtAmountChips
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)

        if draft.cancelsDebt, let debt = draft.selectedDebt {
            cancelBanner(debt)
        }
    }

    private var debtChooserRow: some View {
        Button { showDebtPicker = true } label: {
            HStack(spacing: 12) {
                if let debt = draft.selectedDebt {
                    debtIcon(debt)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Accounting.displayName(debt.merchant))
                            .font(.headline)
                            .foregroundStyle(palette.label)
                            .lineLimit(1)
                        Text(debtSubtitle(debt))
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(palette.warning)
                    Text("Elige la deuda")
                        .foregroundStyle(palette.label)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func debtIcon(_ debt: Expense) -> some View {
        let color = CategoryStyle.color(for: debt.category, accent: themeAccent.color)
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.2))
                .frame(width: 40, height: 40)
            Image(systemName: CategoryStyle.icon(for: debt.category))
                .foregroundStyle(color)
        }
    }

    private func debtSubtitle(_ debt: Expense) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        return "Deuda del " + f.string(from: debt.date) + " · "
            + Money.format(debt.amount, currency: debt.currency) + " original"
    }

    /// Saldo actual → lo que quedaría. El `Picker` anterior mostraba el saldo
    /// dentro del texto de la opción y desaparecía en cuanto elegías.
    private var balanceRow: some View {
        let remainder = draft.debtRemainder ?? 0
        let currency = draft.selectedDebt?.currency ?? draft.currency

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saldo actual")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                Text(Money.format(draft.debtOutstanding ?? 0, currency: currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 20))
                .foregroundStyle(palette.secondaryLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text("Queda")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                Text(Money.format(remainder, currency: currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Money.isZero(remainder) ? palette.positive : palette.label)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
    }

    private var debtAmountChips: some View {
        HStack(spacing: 8) {
            Button { setAmount(draft.debtOutstanding ?? 0) } label: {
                chipLabel("Todo el saldo", tint: accentText, selected: false)
            }
            .buttonStyle(.plain)

            Button { setAmount(Money.divide(draft.debtOutstanding ?? 0, by: 2)) } label: {
                chipLabel("Mitad", tint: palette.secondaryLabel, selected: false)
            }
            .buttonStyle(.plain)

            Button { draft.amountText = "" } label: {
                chipLabel("Otro monto", tint: palette.secondaryLabel, selected: false)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
    }

    private func setAmount(_ value: Double) {
        withAnimation(.easeInOut(duration: 0.15)) {
            draft.amountText = String(format: "%.2f", Money.normalized(value))
            if let debt = draft.selectedDebt { draft.currency = debt.currency }
        }
    }

    private func cancelBanner(_ debt: Expense) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.positive)
            Text("Este abono cancela la deuda. " + Accounting.displayName(debt.merchant)
                 + " dejará de contar como deuda activa.")
                .font(.footnote)
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(palette.positive.opacity(scheme == .dark ? 0.16 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - 5. Botón principal

    @ViewBuilder
    private var primaryButton: some View {
        if undoTarget != nil {
            undoBar
        } else {
            standardButton
        }
    }

    /// Tras el doble toque en un atajo, el gasto ya está guardado; esto da los
    /// segundos para arrepentirse antes de que el modal se cierre solo.
    private var undoBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.positive)
            Text("Guardado")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.label)
            Spacer()
            Button("Deshacer") { undoQuickSave() }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accentText)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var standardButton: some View {
        VStack(spacing: 6) {
            Button(action: save) {
                buttonLabel
            }
            .buttonStyle(.plain)
            .disabled(!draft.validation.isReady || justSaved)
            .accessibilityLabel(buttonAccessibilityLabel)

            // Sobre `#E3E3E8` el texto del botón deshabilitado no llega a
            // 4.5:1; en claro la razón se repite aquí abajo.
            if scheme == .light, let reason = blockedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(palette.background)
    }

    private var blockedReason: String? {
        switch draft.validation {
        case .ready: return nil
        case .blocked(let reason): return reason
        case .invalid(let error): return error
        }
    }

    private var buttonAccessibilityLabel: String {
        blockedReason ?? draft.actionTitle
    }

    @ViewBuilder
    private var buttonLabel: some View {
        let ready = draft.validation.isReady

        HStack(spacing: 8) {
            if justSaved {
                Image(systemName: "checkmark")
                    .symbolEffect(.bounce, value: justSaved)
            }
            Text(justSaved ? "Guardado" : (blockedReason ?? draft.actionTitle))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(.headline)
        .foregroundStyle(ready || justSaved ? Color.white : palette.tertiaryLabel)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(ready || justSaved ? accentFill : palette.track)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .shadow(color: ready ? accentFill.opacity(0.35) : .clear, radius: 18, y: 6)
    }

    private func save() {
        guard draft.validation.isReady else { return }

        if draft.type == .gasto {
            // `isSubscription` ya no se marca a mano: se deriva de la recurrencia.
            draft.isSubscription = recurrence.repeats
            guard let expense = draft.makeExpense() else { return }
            modelContext.insert(expense)

            if let rule = recurrence.build(merchant: expense.merchant,
                                           category: expense.category,
                                           amount: expense.amount,
                                           currency: expense.currency) {
                // El gasto de hoy ya está registrado: la regla arranca marcando
                // esta fecha como resuelta para no proponerla otra vez.
                rule.lastResolvedOccurrence = expense.date
                modelContext.insert(rule)
            }

            if saveAsQuick {
                let quick = QuickExpense(
                    label: Accounting.displayName(expense.merchant),
                    merchant: expense.merchant,
                    category: expense.category,
                    amount: expense.amount,
                    currency: expense.currency,
                    iconName: CategoryStyle.icon(for: expense.category),
                    sortIndex: (quickExpenses.map(\.sortIndex).max() ?? -1) + 1
                )
                modelContext.insert(quick)
            }

            if let id = activeQuickID, let used = quickExpenses.first(where: { $0.id == id }) {
                used.useCount += 1
                used.lastUsedAt = Date()
            }
            // Sin guardar regla de comercio: elegir una categoría para un gasto
            // suelto no debería reescribir la que el usuario fijó en la Bandeja.
            // Para eso está la Bandeja.
        } else {
            guard let income = draft.makeIncome() else { return }
            modelContext.insert(income)
            // `isFinalDebtPayment` se deduce del saldo, no de un toggle: el
            // anterior permitía cerrar una deuda con un abono parcial.
            if draft.cancelsDebt, let debt = draft.selectedDebt {
                debt.isDebt = false
            }
        }
        try? modelContext.save()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { justSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { dismiss() }
    }

    // MARK: - Sheets auxiliares

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Fecha", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Fecha")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") { showDatePicker = false }
                    }
                }
        }
        .presentationDetents([.fraction(0.55)])
        .presentationDragIndicator(.visible)
    }

    private var categoryListSheet: some View {
        NavigationStack {
            List(selectableCategories, id: \.self) { category in
                Button {
                    draft.category = category
                    showAllCategories = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: CategoryStyle.icon(for: category))
                            .foregroundStyle(CategoryStyle.color(for: category, accent: themeAccent.color))
                            .frame(width: 24)
                        Text(category)
                            .foregroundStyle(palette.label)
                        Spacer()
                        if draft.category == category {
                            Image(systemName: "checkmark")
                                .foregroundStyle(accentText)
                        }
                    }
                }
            }
            .navigationTitle("Categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { showAllCategories = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var debtPickerSheet: some View {
        NavigationStack {
            List(activeDebts) { debt in
                Button {
                    draft.selectedDebt = debt
                    draft.currency = debt.currency
                    showDebtPicker = false
                } label: {
                    HStack(spacing: 12) {
                        debtIcon(debt)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Accounting.displayName(debt.merchant))
                                .foregroundStyle(palette.label)
                            Text("saldo " + Money.format(Accounting.outstanding(of: debt), currency: debt.currency))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                        Spacer()
                        if draft.selectedDebt?.id == debt.id {
                            Image(systemName: "checkmark").foregroundStyle(accentText)
                        }
                    }
                }
            }
            .navigationTitle("Deudas activas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { showDebtPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Piezas compartidas

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, 16)
        }
    }

    private func chipLabel(_ text: String, tint: Color, selected: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(palette.surface)
            .clipShape(Capsule())
    }
}

// MARK: - Cursor

/// El cursor parpadeante da la señal de "esto se está escribiendo" que un `Text`
/// no da. Oculto a VoiceOver: no aporta nada leído en voz alta.
struct BlinkingCursor: View {
    let color: Color
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: 44)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
            .accessibilityHidden(true)
    }
}

// MARK: - Teclado numérico

/// Teclado propio en vez de `.keyboardType(.decimalPad)`: no tapa el formulario,
/// no cambia la altura del contenido al aparecer, y permite validar tecla por
/// tecla (dos separadores decimales, más de dos decimales, tope de 9 dígitos).
struct Keypad: View {

    let background: Color
    let onKey: (TransactionDraft.KeypadKey) -> Void
    let onClear: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(1...9, id: \.self) { digit in
                key(label: "\(digit)", accessibility: Keypad.spelled[digit] ?? "\(digit)") {
                    onKey(.digit(digit))
                }
            }

            key(label: ".", accessibility: "Punto decimal") { onKey(.decimal) }
            key(label: "0", accessibility: "Cero") { onKey(.digit(0)) }
            backspaceKey
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(background)
    }

    private static let spelled: [Int: String] = [
        1: "Uno", 2: "Dos", 3: "Tres", 4: "Cuatro", 5: "Cinco",
        6: "Seis", 7: "Siete", 8: "Ocho", 9: "Nueve"
    ]

    private func key(label: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.system(size: 26))
                .foregroundStyle(palette.label)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(keyBackground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var backspaceKey: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onKey(.backspace)
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 22))
                .foregroundStyle(palette.label)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(backspaceBackground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Borrar")
        .onLongPressGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onClear()
        }
    }

    private var keyBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(scheme == .dark ? palette.surface : Color.white)
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.12), radius: 1, y: 1)
    }

    private var backspaceBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(scheme == .dark ? palette.surface : Color(red: 0.835, green: 0.835, blue: 0.859))
    }
}
