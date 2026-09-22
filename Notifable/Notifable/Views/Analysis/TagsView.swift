import SwiftUI
import SwiftData

/// Etiquetas, la hermana de Categorías.
///
/// La regla de lectura, que es lo que decide toda la forma de esta pantalla:
/// **una etiqueta no es una porción del total**. Un gasto puede llevar dos, así
/// que sumar las filas da más que el mes. Por eso aquí no hay dona, ni
/// porcentajes, ni barras comparadas contra el gasto del mes: hay una lista de
/// montos y, al final, la única cifra que sí es disjunta —lo que no lleva
/// ninguna etiqueta—.
///
/// Y por eso tampoco hay límites: un límite sobre algo que se solapa no tiene
/// aritmética. Los límites siguen viviendo en Categorías, bajo cada fila.
struct TagsView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.colorScheme) private var scheme
    @Query private var expenses: [Expense]
    @StateObject private var rates = ExchangeRateService.shared
    @StateObject private var catalog = TagCatalog.shared

    @State private var selectedTag: TagRef?
    @State private var renaming: TagRef?
    @State private var renameDraft = ""
    @State private var merging: TagRef?
    @State private var deleting: TagRef?
    @State private var creating = false
    @State private var createDraft = ""

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var rate: Double { rates.usdToPenRate }
    private var month: Period { Period(granularity: .mes, reference: Date()) }

    private var snapshots: [ExpenseSnapshot] { expenses.map(\.accountingSnapshot) }

    private var rows: [TagTotals.Row] {
        TagTotals.rows(expenses: snapshots, in: month.interval, usdToPen: rate, known: catalog.names)
    }

    /// Las que alguna vez se usaron, en todo el historial: es lo que separa los
    /// dos vacíos de la lista.
    private var everUsed: Set<String> { TagTotals.everUsed(snapshots) }

    private var untagged: Double {
        TagTotals.untagged(expenses: snapshots, in: month.interval, usdToPen: rate)
    }

    var body: some View {
        let rows = self.rows

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 14) {
                ShellTitle(title: "Etiquetas",
                           subtitle: subtitle(rows))

                if rows.isEmpty {
                    ShellEmptyState(icon: "tag",
                                    title: "Aún no hay etiquetas",
                                    message: "Una etiqueta cruza categorías: dos gastos de Salud pueden ser «madre» y «padre». Ábrela desde cualquier movimiento, o créala aquí.")
                } else {
                    list(rows)
                }

                newTagRow

                if Money.cents(untagged) > 0 {
                    ShellNote(icon: "circle.dashed",
                              text: Money.format(untagged) + " de este mes no lleva ninguna etiqueta",
                              tint: palette.secondaryLabel)
                        .padding(.horizontal, 2)
                }

                ShellNote(icon: "info.circle",
                          text: "Un movimiento puede llevar varias etiquetas, así que estas cifras no suman el total del mes. Los límites se ponen por categoría.",
                          tint: palette.tertiaryLabel)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, ShellMetrics.sideInset)
            .padding(.top, ShellMetrics.contentTopInset)
            .padding(.bottom, ShellMetrics.contentBottomInset)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            progress.update(offset)
        }
        .sheet(item: $selectedTag) { ref in
            TagDetailView(tag: ref.name)
        }
        .sheet(item: $merging) { ref in
            TagMergeSheet(source: ref.name, expenses: expenses) { target in
                Task { await TagEditor.merge(ref.name, into: target, in: expenses) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .alert("Nueva etiqueta", isPresented: $creating) {
            TextField("Nombre", text: $createDraft)
            Button("Cancelar", role: .cancel) { createDraft = "" }
            Button("Crear") {
                catalog.use(createDraft)
                createDraft = ""
            }
        } message: {
            Text("La verás al etiquetar cualquier movimiento.")
        }
        .alert("Renombrar etiqueta", isPresented: Binding(get: { renaming != nil },
                                                          set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $renameDraft)
            Button("Cancelar", role: .cancel) { renaming = nil }
            Button("Guardar") { commitRename() }
        } message: {
            Text("Se cambia en todos los movimientos que la lleven.")
        }
        .alert("¿Eliminar etiqueta?", isPresented: Binding(get: { deleting != nil },
                                                           set: { if !$0 { deleting = nil } })) {
            Button("Cancelar", role: .cancel) { deleting = nil }
            Button("Eliminar", role: .destructive) { commitDelete() }
        } message: {
            Text("Los movimientos se quedan donde están, en su categoría de siempre: sólo pierden esta etiqueta.")
        }
    }

    private func subtitle(_ rows: [TagTotals.Row]) -> String {
        guard !rows.isEmpty else { return "Cruzan las categorías sin sustituirlas" }
        let used = rows.filter { $0.count > 0 }.count
        let name = Period.spanishMonthName(for: Date()).lowercased()
        if used == 0 { return "Ninguna se usó en \(name)" }
        return used == 1 ? "1 etiqueta usada en \(name)" : "\(used) etiquetas usadas en \(name)"
    }

    // MARK: - Lista

    private func list(_ rows: [TagTotals.Row]) -> some View {
        let everUsed = self.everUsed

        return MovementCard {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    selectedTag = TagRef(name: row.tag)
                } label: {
                    tagRow(row, everUsed: everUsed)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        renameDraft = row.tag
                        renaming = TagRef(name: row.tag)
                    } label: { Label("Renombrar", systemImage: "pencil") }

                    if catalog.names.count > 1 {
                        Button {
                            merging = TagRef(name: row.tag)
                        } label: { Label("Fusionar con…", systemImage: "arrow.triangle.merge") }
                    }

                    Button(role: .destructive) {
                        deleting = TagRef(name: row.tag)
                    } label: { Label("Eliminar", systemImage: "trash") }
                }

                if index < rows.count - 1 { MovementSeparator() }
            }
        }
    }

    private func tagRow(_ row: TagTotals.Row, everUsed: Set<String>) -> some View {
        let isIdle = row.count == 0
        // Nunca se puso a nada: es la única que necesita un empujón. Una que se
        // usó en otros meses no está pidiendo nada, sólo no tuvo gasto en éste.
        let isUnused = isIdle && !everUsed.contains(TagCatalog.normalized(row.tag))

        return HStack(spacing: 12) {
            Circle()
                .fill(catalog.color(for: row.tag))
                .frame(width: 10, height: 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.tag)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                Text(metaLine(row, isUnused: isUnused))
                    .font(.system(size: 12.5, weight: isUnused ? .semibold : .regular))
                    .foregroundStyle(isUnused ? accent.onSurface(scheme) : palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(Money.format(row.total))
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(isIdle ? palette.tertiaryLabel : palette.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .opacity(isIdle ? 0.6 : 1)
    }

    private func metaLine(_ row: TagTotals.Row, isUnused: Bool) -> String {
        if isUnused { return "Asígnala desde cualquier movimiento" }
        if row.count == 0 { return "Sin movimientos este mes" }
        return row.count == 1 ? "1 movimiento" : "\(row.count) movimientos"
    }

    private var newTagRow: some View {
        Button {
            creating = true
        } label: {
            MovementCard {
                HStack(spacing: 12) {
                    MovementIcon(icon: "plus", color: accent.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nueva etiqueta")
                            .font(.system(size: 16.5, weight: .semibold))
                            .foregroundStyle(palette.label)
                        Text("Se asigna desde cada movimiento")
                            .font(.system(size: 12.5))
                            .foregroundStyle(palette.secondaryLabel)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Acciones

    private func commitRename() {
        guard let tag = renaming?.name else { return }
        let target = renameDraft
        renaming = nil
        Task { await TagEditor.rename(tag, to: target, in: expenses) }
    }

    private func commitDelete() {
        guard let tag = deleting?.name else { return }
        deleting = nil
        Task { await TagEditor.delete(tag, in: expenses) }
    }
}

/// Una etiqueta como `item:` de una hoja o de una alerta, igual que
/// `CategoryRef`: `String` no es `Identifiable`.
struct TagRef: Identifiable, Hashable {
    let name: String
    var id: String { TagCatalog.normalized(name) }
}

// MARK: - Detalle

/// El detalle de una etiqueta.
///
/// Dos preguntas, en este orden: cuánto llevo con ella, y **en qué categorías
/// cae**. Ese segundo bloque es el que justifica la función entera: "madre" se
/// reparte entre Salud y Supermercado, y ahí sí las cifras suman el total de la
/// etiqueta, porque la categoría no se solapa con nada.
///
/// Cierra con «Mantener limpia»: fusionar también vive aquí, no sólo en el menú
/// de la lista. El momento en que uno se da cuenta de que tiene «mamá» y
/// «madre» es justo éste —mirando una de las dos—, no recorriendo la lista.
struct TagDetailView: View {

    let tag: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @StateObject private var rates = ExchangeRateService.shared

    @State private var selectedExpense: Expense?
    @State private var showsAllMovements = false
    @State private var merging = false

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }
    private var month: Period { Period(granularity: .mes, reference: Date()) }
    private var key: String { TagCatalog.normalized(tag) }

    /// Cuántos movimientos se ven antes de «Ver los N»: tres bastan para saber
    /// de qué va la etiqueta, y la lista completa está a un toque.
    private static let previewCount = 3

    private var items: [Expense] {
        let range = month.interval
        return expenses.filter { $0.hasTag(key) && $0.date >= range.start && $0.date < range.end }
    }

    private var total: Double {
        Money.value(items.map(\.accountingSnapshot)
            .reduce(0) { $0 + TagTotals.cost(of: $1, usdToPen: rates.usdToPenRate) })
    }

    private var byCategory: [(category: String, total: Double)] {
        TagTotals.byCategory(tag: tag,
                             expenses: expenses.map(\.accountingSnapshot),
                             in: month.interval,
                             usdToPen: rates.usdToPenRate)
    }

    var body: some View {
        let items = self.items
        let visible = showsAllMovements ? items : Array(items.prefix(Self.previewCount))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero(items: items)

                    if !byCategory.isEmpty {
                        section("En qué categorías cae") {
                            MovementCard {
                                ForEach(Array(byCategory.enumerated()), id: \.offset) { index, row in
                                    categoryRow(row)
                                    if index < byCategory.count - 1 { MovementSeparator() }
                                }
                            }
                        }
                    }

                    if items.isEmpty {
                        ShellEmptyState(icon: "tag",
                                        title: "Sin movimientos este mes",
                                        message: "Etiqueta un gasto desde su ficha y aparecerá aquí.")
                    } else {
                        movements(items: items, visible: visible)
                    }

                    cleanUpSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(palette.background)
            .navigationTitle(tag)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $selectedExpense) { ExpenseDetailsView(expense: $0) }
            .sheet(isPresented: $merging) {
                TagMergeSheet(source: tag, expenses: expenses) { target in
                    Task {
                        await TagEditor.merge(tag, into: target, in: expenses)
                        dismiss()
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
        }
    }

    private func hero(items: [Expense]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(TagCatalog.shared.color(for: tag))
                    .frame(width: 9, height: 9)
                Text(("Etiquetado en " + Period.spanishMonthName(for: Date())).uppercased())
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(palette.secondaryLabel)
            }

            Text(Money.format(total))
                .font(.system(size: 40, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(palette.label)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(items.count == 1 ? "1 movimiento" : "\(items.count) movimientos")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private func section<Content: View>(_ title: String,
                                        trailing: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShellSectionHeader(title: title, trailing: trailing)
            content()
        }
    }

    @ViewBuilder
    private func movements(items: [Expense], visible: [Expense]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("MOVIMIENTOS")
                    .font(.system(size: 11.5, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(palette.secondaryLabel)

                Spacer()

                if items.count > Self.previewCount {
                    Button(showsAllMovements ? "Ver menos" : "Ver los \(items.count)") {
                        withAnimation(.snappy(duration: 0.22)) { showsAllMovements.toggle() }
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent.onSurface(scheme))
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)

            MovementCard {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, expense in
                    Button { selectedExpense = expense } label: {
                        expenseRow(expense)
                    }
                    .buttonStyle(.plain)
                    if index < visible.count - 1 { MovementSeparator() }
                }
            }
        }
    }

    /// Fusionar, a la vista y con su porqué escrito. Escondido en un menú
    /// contextual, el duplicado se queda para siempre: nadie mantiene presionada
    /// una fila para ver qué pasa.
    private var cleanUpSection: some View {
        section("Mantener limpia") {
            MovementCard {
                Button { merging = true } label: {
                    HStack(spacing: 12) {
                        MovementIcon(icon: "arrow.triangle.merge", color: accent.color, size: 34)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fusionar con otra etiqueta")
                                .font(.system(size: 15.5, weight: .semibold))
                                .foregroundStyle(accent.onSurface(scheme))
                            Text("«mamá» y «madre» acaban siendo la misma")
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func categoryRow(_ row: (category: String, total: Double)) -> some View {
        HStack(spacing: 12) {
            MovementIcon(icon: CategoryStyle.icon(for: row.category),
                         color: CategoryStyle.color(for: row.category, accent: accent.color),
                         size: 34)

            Text(row.category)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(palette.label)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(Money.format(row.total))
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(palette.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack(spacing: 12) {
            MovementIcon(icon: CategoryStyle.icon(for: expense.category),
                         color: CategoryStyle.color(for: expense.category, accent: accent.color),
                         size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(Accounting.displayName(expense.merchant))
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)
                Text(expense.category)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryLabel)
            }

            Spacer(minLength: 8)

            Text(Money.format(expense.amount, currency: expense.currency))
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(palette.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
