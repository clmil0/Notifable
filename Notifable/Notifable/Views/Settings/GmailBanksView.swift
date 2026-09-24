import SwiftUI
import SwiftData

/// Gmail y bancos. Antes esto era "Bancos y Sincronización Automática", y
/// mezclaba la cuenta, el progreso, el rango histórico y los cinco bancos en un
/// solo `Form`.
struct GmailBanksView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    /// Recuerda el último periodo elegido para que "Leer" no vuelva a "1 mes"
    /// cada vez que se abre la pantalla.
    @AppStorage("readPeriodMonths") private var readPeriodMonths = 1

    @StateObject private var gmailAuth = GmailAuthService.shared
    @StateObject private var gmailSync = GmailSyncService.shared

    /// Sólo para el rótulo del botón mientras se va y se vuelve de Google. La
    /// secuencia de después de conectar la presenta `SettingsView`, que es la
    /// raíz de este `fullScreenCover`.
    @State private var isLinking = false

    @State private var showUnlinkDialog = false
    @State private var showRecoveryAlert = false
    /// El chip "Personalizado" abre el stepper; no cambia `readPeriodMonths`
    /// por sí solo, así que el valor puede seguir siendo uno de los estándar.
    @State private var showCustomStepper = false
    /// Se guarda aquí para que los `Toggle` redibujen: `BankSource.isEnabled`
    /// escribe en `UserDefaults` y no publica cambios por sí solo.
    @State private var bankStates: [String: Bool] = [:]

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    private static let standardPeriods = [1, 3, 12]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                accountCard
                if gmailAuth.isAuthenticated {
                    readingSection
                }
                banksSection
                captureLimitsCard
            }
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle("Gmail y bancos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadBankStates()
            showCustomStepper = !Self.standardPeriods.contains(readPeriodMonths)
        }
        .onReceive(gmailAuth.$isAuthenticated) { isAuthenticated in
            if isAuthenticated { isLinking = false }
        }
        // Cancelar en la pantalla de Google no avisa de nada: si al volver
        // seguimos sin cuenta, el botón se destraba solo. La espera es para no
        // pisar el caso normal, donde el token llega poco después de reactivar.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, isLinking else { return }
            Task {
                try? await Task.sleep(for: .seconds(5))
                if !gmailAuth.isAuthenticated || gmailAuth.missingGmailScope { isLinking = false }
            }
        }
        .confirmationDialog("¿Desvincular Gmail?",
                            isPresented: $showUnlinkDialog,
                            titleVisibility: .visible) {
            Button("Desvincular", role: .destructive) { gmailAuth.signOut() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los gastos ya registrados se conservan. Dejarán de entrar nuevos.")
        }
        .alert("Recuperación de Gastos", isPresented: $showRecoveryAlert) {
            Button("Sí, recuperar") {
                let recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                gmailSync.recoverExpenses(ids: recoveryIDs)
            }
            Button("No (Descartar)") {
                UserDefaults.standard.removeObject(forKey: "pendingRecoveryIDs")
                startSync()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Has borrado elementos anteriores. ¿Quieres recuperarlos antes de continuar con la lectura?")
        }
    }

    // MARK: - Cuenta

    /// Conectada, pero sin la casilla de Gmail: ver `GmailAuthService.missingGmailScope`.
    private var lacksPermission: Bool { gmailAuth.isAuthenticated && gmailAuth.missingGmailScope }

    private var accountTint: Color {
        lacksPermission ? palette.negative
            : gmailAuth.isAuthenticated ? palette.positive : palette.tertiaryLabel
    }

    @ViewBuilder
    private var accountCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accountTint.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(accountTint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // La cuenta concreta y no "Gmail vinculado": quien tiene
                    // varias quiere saber cuál está leyendo la app.
                    Text(gmailAuth.isAuthenticated || gmailAuth.accessRevoked
                         ? (gmailAuth.accountEmail ?? "Gmail vinculado") : "Gmail sin vincular")
                        .font(.headline)
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .minimumScaleFactor(0.8)
                    Text(lacksPermission
                         ? "Falta el permiso para leer tus correos. Vuelve a conectar y marca la casilla de Gmail."
                         : gmailAuth.isAuthenticated
                         ? "● Conectado · sólo lectura"
                         : gmailAuth.accessRevoked
                            ? "Google cortó el acceso. Vuelve a vincular para seguir leyendo tus avisos."
                            : "AgruPay lee los avisos de tu banco para registrar gastos solo.")
                        .font(.footnote)
                        .foregroundStyle(lacksPermission ? palette.negative
                                         : gmailAuth.isAuthenticated ? palette.positive
                                         : gmailAuth.accessRevoked ? palette.negative : palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                // Desvincular vive aquí y no en una fila al final: es una
                // acción sobre esta cuenta, y al pie parecía aplicar a toda la
                // pantalla (bancos y periodo incluidos).
                if gmailAuth.isAuthenticated {
                    Button { showUnlinkDialog = true } label: {
                        Text("Desvincular")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.negative)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            if !gmailAuth.isAuthenticated || lacksPermission {
                Rectangle().fill(palette.separator).frame(height: 0.5)
                Button {
                    isLinking = true
                    gmailAuth.signIn()
                } label: {
                    Text(isLinking ? "Conectando…" : lacksPermission ? "Volver a conectar" : "Vincular Gmail")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(accent.color)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Lectura

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LECTURA")
                .font(.system(size: 11.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 22)

            Group {
                if gmailSync.isSyncing { syncProgress } else { lastReadRow }
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(palette.hairline, lineWidth: 0.5))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Selector de periodo de lectura

    /// Reemplaza al único botón "Leer ahora": aquí se elige desde cuándo leer,
    /// no sólo se dispara una lectura con el rango que ya traía por defecto.
    private var lastReadRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                // Se redibuja sola: la lectura corre cada minuto con la app
                // abierta y "hace 6 min" no puede quedarse congelado en pantalla.
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    (Text("Última lectura · ")
                        .foregroundStyle(palette.secondaryLabel)
                     + Text(lastSyncLabel)
                        .foregroundStyle(palette.label)
                        .fontWeight(.semibold))
                        .font(.caption)
                }
                Spacer()
                Text("\(cachedEmailCount.formatted()) correos")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.tertiaryLabel)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("CUÁNTO ATRÁS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.tertiaryLabel)

                HStack(spacing: 6) {
                    ForEach(Self.standardPeriods, id: \.self) { months in
                        periodChip(label: periodChipLabel(months), isActive: !showCustomStepper && readPeriodMonths == months) {
                            showCustomStepper = false
                            readPeriodMonths = months
                        }
                    }
                    periodChip(label: "Otro", isActive: showCustomStepper) {
                        showCustomStepper = true
                    }
                }
            }

            if showCustomStepper {
                HStack {
                    Text("Cuánto atrás")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    Spacer()
                    HStack(spacing: 0) {
                        // "−" se aleja en el tiempo (suma un mes hacia atrás);
                        // "+" acerca el inicio del rango a hoy.
                        stepperButton(systemName: "minus") {
                            readPeriodMonths = min(36, readPeriodMonths + 1)
                        }
                        Text("\(readPeriodMonths)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.label)
                            .frame(minWidth: 28)
                        stepperButton(systemName: "plus") {
                            readPeriodMonths = max(1, readPeriodMonths - 1)
                        }
                    }
                    .padding(.horizontal, 4)
                    .background(palette.track)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

            Text(rangeLabel + " · sin duplicar lo que ya tienes")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)

            // Sin esto una lectura que fallaba o no encontraba nada se veía
            // igual: la barra aparecía y se iba al segundo.
            if let error = gmailSync.lastSyncError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(palette.negative)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let summary = gmailSync.lastRunSummary {
                Label(summary, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                gmailSync.modelContext = modelContext
                let recoveryIDs = UserDefaults.standard.stringArray(forKey: "pendingRecoveryIDs") ?? []
                if !recoveryIDs.isEmpty {
                    showRecoveryAlert = true
                } else {
                    startSync()
                }
            } label: {
                Label("Leer ahora", systemImage: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.onSurface(scheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(accent.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private func periodChip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? .white : palette.label)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(isActive ? accent.color : palette.neutralSurface)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.label)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func startSync() {
        gmailSync.syncEmails(force: true, startDate: rangeStartDate, endDate: Date())
    }

    /// Abreviado para los chips: cinco opciones tienen que caber en una fila.
    /// "3 meses" y "Personalizado" desbordaban y la fila se veía rota. El botón
    /// de abajo sí dice el periodo completo, que es donde importa.
    private func periodChipLabel(_ months: Int) -> String {
        periodLabel(months)
    }

    /// "1 mes" / "3 meses" / "1 año" / "2 años" / "N meses" para el resto.
    private func periodLabel(_ months: Int) -> String {
        if months == 12 { return "1 año" }
        if months > 0, months % 12 == 0 { return "\(months / 12) años" }
        return months == 1 ? "1 mes" : "\(months) meses"
    }

    private var rangeStartDate: Date {
        GmailSyncService.smartRangeStart(months: readPeriodMonths)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        var text = f.string(from: date)
        let cal = Calendar.current
        if cal.component(.year, from: date) != cal.component(.year, from: Date()) {
            text += ", " + String(cal.component(.year, from: date))
        }
        return text
    }

    private var rangeLabel: String {
        "\(formatted(rangeStartDate)) → hoy, \(formatted(Date()))"
    }

    private var cachedEmailCount: Int {
        (UserDefaults.standard.stringArray(forKey: "processedEmailIDs") ?? []).count
    }

    private var lastSyncLabel: String {
        SettingsStatus(isConnected: true, account: nil, lastSync: gmailSync.lastSyncDate,
                       activeBankCount: 0, totalBankCount: 0, expensesThisMonth: 0,
                       unclassifiedMerchants: 0, pendingRecurring: 0).lastSyncLabel
    }

    /// El bloque de progreso que ya existía, conservado tal cual.
    private var syncProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Buscando nuevos gastos...")
                .font(.headline)
                .foregroundStyle(palette.label)

            ProgressView(value: Double(gmailSync.emailsProcessed),
                         total: Double(max(1, gmailSync.totalEmailsToProcess)))
                .progressViewStyle(LinearProgressViewStyle())
                .animation(.easeInOut, value: gmailSync.emailsProcessed)

            Text("\(gmailSync.emailsProcessed) de \(gmailSync.totalEmailsToProcess) correos procesados")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)

            if !gmailSync.expensesFoundByBank.isEmpty {
                Divider()
                Text("Gastos identificados:")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.label)

                ForEach(Array(gmailSync.expensesFoundByBank.keys.sorted()), id: \.self) { bank in
                    HStack {
                        Text(bank)
                        Spacer()
                        Text("\(gmailSync.expensesFoundByBank[bank] ?? 0)")
                            .fontWeight(.bold)
                    }
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Bancos

    /// Sin `info.circle` dentro del `Toggle`: la descripción es un subtítulo, así
    /// que tocar el nombre ya no alterna el banco por accidente. Y los cinco
    /// usan el acento del usuario, no cinco colores fijos.
    private var banksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "Bancos que se leen" sonaba a que la app había encontrado
            // cuentas en esos bancos: quien no tiene Scotiabank se asustaba al
            // verlo. Se aclara antes de la lista que es lo que AgruPay sabe
            // leer, no dónde tiene cuentas el usuario.
            VStack(alignment: .leading, spacing: 4) {
                Text("BANCOS COMPATIBLES")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                Text("Son los bancos cuyos avisos AgruPay sabe leer. No significa que tengas cuenta en ellos: si no usas alguno, simplemente no llegará nada suyo.")
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(BankSource.all.enumerated()), id: \.element.id) { index, bank in
                    bankRow(bank)
                    if index < BankSource.all.count - 1 {
                        Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 16)
                    }
                }
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)

        }
    }

    private func bankRow(_ bank: BankSource) -> some View {
        let isOn = bankStates[bank.storageKey] ?? bank.isEnabled

        return HStack(spacing: 12) {
            Image(bank.logoAsset)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isOn ? 1 : 0.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(bank.name)
                    .foregroundStyle(isOn ? palette.label : palette.secondaryLabel)
                Text(bank.subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: binding(for: bank))
                .labelsHidden()
                .tint(accent.color)
                .accessibilityLabel(bank.name)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func binding(for bank: BankSource) -> Binding<Bool> {
        Binding(
            get: { bankStates[bank.storageKey] ?? bank.isEnabled },
            set: { newValue in
                bank.isEnabled = newValue
                bankStates[bank.storageKey] = newValue
            }
        )
    }

    private func loadBankStates() {
        for bank in BankSource.all where bankStates[bank.storageKey] == nil {
            bankStates[bank.storageKey] = bank.isEnabled
        }
    }

    // MARK: - Límites de la captura

    /// Cierra el círculo con los atajos: el hueco se cuenta justo donde se nota.
    private var captureLimitsCard: some View {
        NavigationLink {
            RecurringManagementView()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(palette.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("El efectivo y los Yape pequeños no llegan por correo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.label)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Regístralos con un atajo de un toque.")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(14)
            .background(palette.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.warning.opacity(0.35), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // El botón de desvincular vive dentro de `accountCard`, en la misma fila
    // que la cuenta vinculada.
}
