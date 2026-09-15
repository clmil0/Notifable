#if DEBUG
import SwiftUI
import FinanceKit

/// POC: qué ve FinanceKit de la billetera de este iPhone.
///
/// Sólo existe en DEBUG. Necesita el entitlement administrado
/// `com.apple.developer.financekit` (Apple lo aprueba a pedido) y
/// `NSFinancialDataUsageDescription` en el Info.plist. Sin el entitlement,
/// FinanceKit no lanza error: mata el proceso ("Process is not entitled").
/// Por eso nada toca `FinanceStore.shared` salvo que se compile con
/// `FINANCEKIT_ENTITLED` en Active Compilation Conditions.
struct FinanceKitPOCView: View {
    #if FINANCEKIT_ENTITLED
    private let entitled = true
    #else
    private let entitled = false
    #endif

    @State private var dataAvailable = FinanceStore.isDataAvailable(.financialData)
    @State private var status: String = "—"
    @State private var accounts: [Account] = []
    @State private var balances: [UUID: String] = [:]
    @State private var transactions: [FinanceKit.Transaction] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            Section("Disponibilidad") {
                LabeledContent("Datos financieros", value: dataAvailable ? "Sí" : "No")
                LabeledContent("Entitlement", value: entitled ? "Declarado" : "No")
                LabeledContent("Autorización", value: status)
                if !entitled {
                    Text("Sin el entitlement com.apple.developer.financekit, cualquier llamada a FinanceStore cierra la app. Cuando Apple lo apruebe, agrégalo en Signing & Capabilities y añade FINANCEKIT_ENTITLED a Active Compilation Conditions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !dataAvailable {
                    Text("FinanceKit no está disponible en este dispositivo o región. Hoy sólo expone Apple Card, Apple Cash y Apple Savings (EE. UU.) y cuentas conectadas del Reino Unido.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(loading ? "Leyendo…" : "Pedir acceso y leer") {
                    Task { await load() }
                }
                .disabled(loading || !dataAvailable || !entitled)
            }

            if let error {
                Section("Error") {
                    Text(error).font(.footnote.monospaced())
                }
            }

            if !accounts.isEmpty {
                Section("Cuentas (\(accounts.count))") {
                    ForEach(accounts) { account in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName).font(.headline)
                            Text("\(account.institutionName) · \(kind(of: account)) · \(account.currencyCode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let balance = balances[account.id] {
                                Text(balance).font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
            }

            if !transactions.isEmpty {
                Section("Últimos movimientos (\(transactions.count))") {
                    ForEach(transactions) { tx in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(tx.merchantName ?? tx.transactionDescription)
                                    .lineLimit(1)
                                Spacer()
                                Text(format(tx.transactionAmount, credit: tx.creditDebitIndicator == .credit))
                                    .monospacedDigit()
                                    .foregroundStyle(tx.creditDebitIndicator == .credit ? .green : .primary)
                            }
                            Text("\(tx.transactionDate.formatted(date: .abbreviated, time: .shortened)) · \(String(describing: tx.transactionType)) · \(String(describing: tx.status))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let mcc = tx.merchantCategoryCode {
                                Text("MCC \(String(describing: mcc))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("FinanceKit (POC)")
        .task { await refreshStatus() }
    }

    // MARK: - Lectura

    private func refreshStatus() async {
        guard entitled else { return }
        do {
            status = describe(try await FinanceStore.shared.authorizationStatus())
        } catch {
            status = "Error"
            self.error = String(describing: error)
        }
    }

    private func load() async {
        guard entitled else { return }
        loading = true
        defer { loading = false }
        error = nil

        let store = FinanceStore.shared
        do {
            let auth = try await store.requestAuthorization()
            status = describe(auth)
            guard auth == .authorized else { return }

            accounts = try await store.accounts(query: AccountQuery())

            let rawBalances = try await store.accountBalances(query: AccountBalanceQuery())
            // Un saldo por cuenta basta para ver qué expone.
            var latest: [UUID: String] = [:]
            for balance in rawBalances where latest[balance.accountID] == nil {
                latest[balance.accountID] = describe(balance.currentBalance)
            }
            balances = latest

            transactions = try await store.transactions(query: TransactionQuery(
                sortDescriptors: [SortDescriptor(\.transactionDate, order: .reverse)],
                limit: 100
            ))
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Formato

    private func kind(of account: Account) -> String {
        switch account {
        case .asset: "Activo"
        case .liability: "Pasivo"
        @unknown default: "Otro"
        }
    }

    private func describe(_ status: AuthorizationStatus) -> String {
        switch status {
        case .authorized: "Autorizado"
        case .denied: "Denegado"
        case .notDetermined: "Sin decidir"
        @unknown default: "Desconocido"
        }
    }

    private func describe(_ balance: CurrentBalance) -> String {
        switch balance {
        case .available(let b): "Disponible \(format(b.amount, credit: b.creditDebitIndicator == .credit))"
        case .booked(let b): "Contable \(format(b.amount, credit: b.creditDebitIndicator == .credit))"
        case .availableAndBooked(let a, let b):
            "Disponible \(format(a.amount, credit: a.creditDebitIndicator == .credit)) · Contable \(format(b.amount, credit: b.creditDebitIndicator == .credit))"
        @unknown default: "—"
        }
    }

    private func format(_ amount: CurrencyAmount, credit: Bool) -> String {
        let text = amount.amount.formatted(.currency(code: amount.currencyCode))
        return credit ? "+\(text)" : "-\(text)"
    }
}
#endif
