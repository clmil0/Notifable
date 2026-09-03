import SwiftUI

/// Los dos controles del presupuesto. Viven en un solo sitio porque se muestran
/// en dos: la sección de Ajustes y el sheet que abre "Definir presupuesto
/// mensual" desde la tarjeta principal.
struct BudgetSettingsSection: View {

    @AppStorage(BudgetStore.enabledKey) private var budgetEnabled = true
    @AppStorage(BudgetStore.monthlyBudgetKey) private var monthlyBudget: Double = 0
    @AppStorage(BudgetStore.tracksIncomeKey) private var tracksIncome = true

    @State private var amountText: String = ""
    @FocusState private var amountFocused: Bool

    var tint: Color = .purple

    var body: some View {
        Section {
            Toggle("Usar presupuesto", isOn: $budgetEnabled)
                .tint(tint)

            if budgetEnabled {
                HStack {
                    Text("Presupuesto mensual")
                    Spacer()
                    Text("S/")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                        .focused($amountFocused)
                        .onChange(of: amountText) { _, newValue in
                            commit(newValue)
                        }
                }
            }

            Toggle("Registrar ingresos", isOn: $tracksIncome)
                .tint(tint)
        } header: {
            Text("Presupuesto")
        } footer: {
            Text(tracksIncome
                 ? "El presupuesto se prorratea al periodo que estés viendo."
                 : "Si lo apagas, AgruPay usa sólo tu presupuesto.")
        }
        .onAppear {
            amountText = Money.isZero(monthlyBudget) ? "" : String(format: "%.2f", monthlyBudget)
        }
    }

    /// Se normaliza a céntimos al guardar, no al teclear: así el usuario puede
    /// escribir "1200." sin que el campo le borre el punto.
    private func commit(_ text: String) {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned) else {
            if cleaned.isEmpty { monthlyBudget = 0 }
            return
        }
        monthlyBudget = Money.normalized(max(0, value))
    }
}

/// El mismo formulario en un sheet, para definir el presupuesto sin salir de
/// Resumen la primera vez.
struct BudgetSheet: View {

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    private var tint: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }

    var body: some View {
        NavigationStack {
            Form {
                BudgetSettingsSection(tint: tint)
            }
            .navigationTitle("Presupuesto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .appAppearance()
            .appTextSize()
        }
        .presentationDetents([.fraction(0.45)])
        .presentationDragIndicator(.visible)
    }
}
