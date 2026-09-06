import SwiftUI

/// Ajuste del bloqueo con Face ID / Touch ID.
///
/// El interruptor no escribe la preferencia directamente: pide autenticarse y
/// sólo entonces la guarda, tanto para encender como para apagar. Por eso no es
/// un `@AppStorage` atado al `Toggle`, sino un `Binding` con acción.
struct AppLockSettingsView: View {

    @StateObject private var lock = AppLock.shared
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    @State private var isWorking = false
    @State private var error: String?

    private var tint: Color { (AppThemeColor(rawValue: appAccentColor) ?? .purple).color }

    var body: some View {
        Form {
            if AppLock.canLock {
                Section {
                    Toggle(isOn: toggleBinding) {
                        Label("Pedir " + AppLock.biometryName + " al abrir",
                              systemImage: AppLock.biometryIcon)
                    }
                    .tint(tint)
                    .disabled(isWorking)
                } footer: {
                    Text(lock.isEnabled
                         ? "Al abrir AgruPay habrá que verificar la identidad. Si \(AppLock.biometryName) falla, iOS ofrece el código del iPhone."
                         : "Tus movimientos, deudas y sueldo quedan detrás de \(AppLock.biometryName). No cifra nada nuevo: los datos ya están protegidos por el cifrado del iPhone.")
                }

                if lock.isEnabled {
                    Section {
                        Picker("Bloquear", selection: graceBinding) {
                            ForEach(AppLock.Grace.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } footer: {
                        Text("Con un margen, salir un momento a otra app y volver no vuelve a pedir la verificación.")
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Section {
                    Label("Sin código en este iPhone", systemImage: "lock.slash")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Para bloquear AgruPay hace falta un código de desbloqueo en el iPhone. Se configura en Ajustes de iOS → Face ID y código.")
                }
            }
        }
        .navigationTitle("Bloqueo")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Encender y apagar pasan por `AppLock`, que exige autenticarse antes de
    /// tocar la preferencia. El `Toggle` sólo dispara la intención.
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { lock.isEnabled },
            set: { wanted in
                guard wanted != lock.isEnabled, !isWorking else { return }
                Task {
                    isWorking = true
                    error = wanted ? await lock.enable() : await lock.disable()
                    isWorking = false
                }
            }
        )
    }

    private var graceBinding: Binding<AppLock.Grace> {
        Binding(get: { lock.grace }, set: { lock.setGrace($0) })
    }
}
