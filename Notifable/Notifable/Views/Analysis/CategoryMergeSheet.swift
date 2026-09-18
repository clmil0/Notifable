import SwiftUI
import SwiftData

/// Elegir a qué categoría fusionar otra. La usan el detalle de categoría y
/// Categorías y reglas, con la misma promesa: nada se borra.
struct CategoryMergeSheet: View {
    let source: String
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @State private var targets: [String] = []
    @State private var isWorking = false

    private var accent: AppThemeColor { .current }
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(targets, id: \.self) { target in
                        Button { merge(into: target) } label: {
                            HStack(spacing: 12) {
                                MovementIcon(icon: CategoryStyle.icon(for: target),
                                             color: CategoryStyle.color(for: target, accent: accent.color),
                                             size: 32)
                                Text(target).foregroundStyle(palette.label)
                            }
                        }
                        .disabled(isWorking)
                    }
                } footer: {
                    Text("Sus movimientos y reglas pasan a la categoría que elijas, y los límites se suman. Nada se borra.")
                }
            }
            .overlay { if isWorking { ProgressView().controlSize(.large) } }
            .navigationTitle("Fusionar «\(source)» con…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear(perform: loadTargets)
        }
    }

    private func loadTargets() {
        var descriptor = FetchDescriptor<Expense>()
        descriptor.propertiesToFetch = [\.category]
        let used = Set(((try? modelContext.fetch(descriptor)) ?? []).map(\.category))
        let custom = Set(CategoryCatalog.shared.entries.keys)
        targets = used.union(custom)
            .subtracting([source, Accounting.unclassified])
            .sorted()
    }

    private func merge(into target: String) {
        isWorking = true
        let source = self.source
        Task {
            let affected = (try? modelContext.fetch(FetchDescriptor<Expense>(
                predicate: #Predicate { $0.category == source }))) ?? []
            await CategoryEditor.merge(source, into: target, in: affected)
            try? modelContext.save()
            isWorking = false
            dismiss()
            onDone()
        }
    }
}
