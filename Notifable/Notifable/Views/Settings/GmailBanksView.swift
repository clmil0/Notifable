import SwiftUI
import SwiftData

/// Gmail y bancos. Antes esto era "Bancos y Sincronización Automática", y
/// mezclaba la cuenta, el progreso, el rango histórico y los cinco bancos en un
/// solo `Form`.
struct GmailBanksView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    @StateObject private var gmailAuth = GmailAuthService.shared
    @StateObject private var gmailSync = GmailSyncService.shared

    @State private var showUnlinkDialog = false
    /// Se guarda aquí para que los `Toggle` redibujen: `BankSource.isEnabled`
    /// escribe en `UserDefaults` y no publica cambios por sí solo.
    @State private var bankStates: [String: Bool] = [:]

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                accountCard
                banksSection
                captureLimitsCard

                if gmailAuth.isAuthenticated {
                    unlinkRow
                }
            }
            .padding(.vertical, 16)
        }
        .background(palette.background)
        .navigationTitle("Gmail y bancos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadBankStates)
        .confirmationDialog("¿Desvincular Gmail?",
                            isPresented: $showUnlinkDialog,
                            titleVisibility: .visible) {
            Button("Desvincular", role: .destructive) { gmailAuth.signOut() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los gastos ya registrados se conservan. Dejarán de entrar nuevos.")
        }
    }

    // MARK: - Cuenta

    @ViewBuilder
    private var accountCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((gmailAuth.isAuthenticated ? palette.positive : palette.tertiaryLabel).opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(gmailAuth.isAuthenticated ? palette.positive : palette.tertiaryLabel)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(gmailAuth.isAuthenticated ? "Gmail vinculado" : "Gmail sin vincular")
                        .font(.headline)
                        .foregroundStyle(palette.label)
                    Text(gmailAuth.isAuthenticated
                         ? "Conectado · sólo lectura"
                         : "AgruPay lee los avisos de tu banco para registrar gastos solo.")
                        .font(.footnote)
                        .foregroundStyle(gmailAuth.isAuthenticated ? palette.positive : palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(16)

            Rectangle().fill(palette.separator).frame(height: 0.5)

            if gmailAuth.isAuthenticated {
                if gmailSync.isSyncing {
                    syncProgress
                } else {
                    lastReadRow
                }
            } else {
                Button {
                    gmailAuth.signIn()
                } label: {
                    Text("Vincular Gmail")
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }

    private var lastReadRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Última lectura")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                Text(lastSyncLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
            }

            Spacer()

            Button {
                gmailSync.modelContext = modelContext
                gmailSync.syncEmails(force: true)
            } label: {
                Text("Leer ahora")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(accent.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
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
            Text("BANCOS QUE SE LEEN")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .padding(.horizontal, 16)

            Text("Lo que cada banco detecta va bajo su nombre, no detrás de un botón de info dentro del interruptor.")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, 20)
        }
    }

    private func bankRow(_ bank: BankSource) -> some View {
        let isOn = bankStates[bank.storageKey] ?? bank.isEnabled

        return HStack(spacing: 12) {
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

    // MARK: - Desvincular

    private var unlinkRow: some View {
        Button { showUnlinkDialog = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle")
                Text("Desvincular Gmail")
                Spacer()
            }
            .font(.body)
            .foregroundStyle(palette.negative)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.negative.opacity(0.35), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}
