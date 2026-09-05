import SwiftUI
import SwiftData

/// Datos y respaldo. El CSV vivía en una sección llamada "Funciones Online"
/// junto a dos toggles de IA que no hacían nada; las acciones destructivas
/// compartían sección con el diagnóstico BBVA, las dos en naranja.
struct DataBackupView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    @Query private var expenses: [Expense]
    @StateObject private var gmailSync = GmailSyncService.shared
    @State private var syncManager = ConfigBackupManager.shared
    @State private var summary = BackupSummary()
    @State private var showBackupDetail = false
    @State private var showEnableSyncHint = false
    @State private var isBackingUp = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    private var ruleCount: Int { MerchantRules.all().count }
    private var cachedEmailCount: Int {
        (UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []).count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                backupCard
                inventory
                configBackupRow
                deleteDataRow
                debugSection
            }
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle("Datos y respaldo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $gmailSync.showDiagnostic) {
            NavigationStack {
                ScrollView {
                    Text(gmailSync.diagnosticResult)
                        .padding()
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .navigationTitle("Diagnóstico")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { gmailSync.showDiagnostic = false }
                    }
                }
            }
        }
    }

    // MARK: - Qué se guarda

    /// Antes decía "412 gastos en este dispositivo" junto a un botón que los
    /// subía a la nube. Los gastos ya no se suben —se rearman releyendo el
    /// correo— así que ese número prometía justo lo contrario de lo que pasa.
    /// Ahora cuenta lo que sí viaja: ajustes, deudas y lo anotado a mano.
    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.color.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "icloud.and.arrow.up")
                        .foregroundStyle(accent.onSurface(scheme))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lo que se guarda")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { showBackupDetail.toggle() }
                } label: {
                    Image(systemName: showBackupDetail ? "info.circle.fill" : "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(showBackupDetail ? accent.onSurface(scheme) : palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
            }

            if showBackupDetail {
                VStack(spacing: 0) {
                    ForEach(summary.rows) { row in
                        HStack(spacing: 10) {
                            Image(systemName: row.icon)
                                .font(.caption)
                                .frame(width: 18)
                                .foregroundStyle(accent.onSurface(scheme))
                            Text(row.title)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                            Spacer(minLength: 8)
                            Text("\(row.count)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(palette.label)
                        }
                        .frame(height: 30)
                    }
                    Text("Tus gastos e ingresos del correo no se suben: se vuelven a leer solos.")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .transition(.opacity)
            }

            HStack(spacing: 10) {
                secondaryButton(isBackingUp ? "Guardando…" : "Respaldar ahora",
                                icon: "arrow.triangle.2.circlepath") {
                    guard syncManager.isEnabled else {
                        showEnableSyncHint = true
                        return
                    }
                    Task {
                        isBackingUp = true
                        _ = await syncManager.syncNow()
                        summary = syncManager.localSummary()
                        isBackingUp = false
                    }
                }
                secondaryButton("Exportar CSV", icon: "square.and.arrow.up") {
                    // TODO: Implement CSV Export
                }
            }

            if showEnableSyncHint {
                Text("Primero activa la sincronización aquí abajo: sin ella no hay dónde guardarlo.")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .task { summary = syncManager.localSummary() }
        .onChange(of: syncManager.lastSyncedAt) { _, _ in
            summary = syncManager.localSummary()
        }
    }

    private var summaryLine: String {
        let total = summary.total
        guard total > 0 else { return "Todavía no has configurado nada que guardar." }
        return "\(total) cosas: ajustes, cobros y lo anotado a mano"
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.label)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(palette.track)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inventario

    /// El contexto que hace comprensible el bloque de abajo: sin saber cuántos
    /// gastos hay, "borrar todo" no significa nada.
    private var inventory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EN ESTE DISPOSITIVO")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                inventoryRow("Gastos", value: "\(expenses.count)")
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                inventoryRow("Reglas de categoría", value: "\(ruleCount)")
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                inventoryRow("Correos en caché", value: "\(cachedEmailCount)")
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }

    private func inventoryRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(palette.label)
            Spacer()
            Text(value).foregroundStyle(palette.secondaryLabel)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: - Sincronización

    /// El estado vive en el subtítulo de la fila: entrar a la pantalla sólo
    /// para comprobar que todo va bien es un viaje que no debería hacer falta.
    private var syncIcon: String {
        if syncManager.lastErrorMessage != nil { return "exclamationmark.icloud.fill" }
        if syncManager.isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        if syncManager.isEnabled { return "checkmark.icloud.fill" }
        return syncManager.isPausedAfterWipe ? "pause.circle.fill" : "icloud.slash"
    }

    private var syncTint: Color {
        if syncManager.lastErrorMessage != nil { return palette.negative }
        if !syncManager.isEnabled { return palette.secondaryLabel }
        return accent.onSurface(scheme)
    }

    private var syncSubtitle: String {
        if let error = syncManager.lastErrorMessage { return error }
        if syncManager.isSyncing { return "Sincronizando…" }
        if syncManager.isEnabled {
            guard let last = syncManager.lastSyncedAt else { return "Activada" }
            let ago = Self.relative.localizedString(for: last, relativeTo: Date())
            return "Activada · \(ago)"
        }
        return syncManager.isPausedAfterWipe ? "Pausada" : "Desactivada"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    // MARK: - Respaldo de configuración

    /// Reglas, categorías (con sus renombrados), presupuestos, bancos
    /// activos, notificaciones, apariencia, atajos y gastos recurrentes —
    /// todo lo que sobra si formateas el celular y no lo puedes recuperar
    /// releyendo el correo.
    private var configBackupRow: some View {
        NavigationLink {
            ConfigBackupView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(syncTint.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: syncIcon)
                        .foregroundStyle(syncTint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sincronización")
                        .foregroundStyle(palette.label)
                    Text(syncSubtitle)
                        .font(.caption)
                        .foregroundStyle(syncManager.lastErrorMessage == nil ? palette.secondaryLabel : palette.negative)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Borrar datos

    /// Ya no hay una lista plana de acciones irreversibles aquí: la elección
    /// por intención (qué quieres conseguir) vive en DeleteDataView.
    private var deleteDataRow: some View {
        NavigationLink {
            DeleteDataView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.negative.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: "trash.fill")
                        .foregroundStyle(palette.negative)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Borrar datos")
                        .foregroundStyle(palette.negative)
                    Text("Elige qué borrar por grupos.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.negative.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Debug

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 8) {
            Text("DEBUG")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                debugRow("Diagnóstico BBVA Pago", icon: "stethoscope") { gmailSync.diagnosticBBVA() }
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                debugRow("Diagnóstico BBVA Transf", icon: "arrow.left.arrow.right") { gmailSync.diagnosticBBVATransfer() }
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                debugRow("Diagnóstico Apple", icon: "apple.logo") { gmailSync.diagnosticApple() }
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                debugRow("Añadir gasto de prueba", icon: "dice", action: addRandomExpense)
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
        }
        #endif
    }

    #if DEBUG
    private func debugRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24)
                Text(title)
                Spacer()
            }
            .foregroundStyle(palette.secondaryLabel)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addRandomExpense() {
        let options = [
            ("Apple Store", "Entretenimiento"),
            ("Starbucks", "Comida"),
            ("Uber", "Transporte"),
            ("Wong", "Supermercado"),
            ("Netflix", "Entretenimiento"),
            ("Oxxo 123", Accounting.unclassified)
        ]
        let selected = options.randomElement()!
        let days = Int.random(in: 0...20)
        let date = Period.calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let expense = Expense(
            amount: Double.random(in: 10.0...150.0),
            merchant: selected.0,
            date: date,
            category: selected.1,
            isSubscription: selected.0 == "Netflix"
        )
        modelContext.insert(expense)
        try? modelContext.save()
    }
    #endif
}
