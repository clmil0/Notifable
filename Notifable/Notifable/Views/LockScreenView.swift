import SwiftUI

/// La puerta. Mismo lenguaje visual que el splash —fondo de marca y el glifo
/// del sobre— para que no parezca una pantalla de otra app.
///
/// No enseña **nada** del contenido: ni el total del mes, ni el último
/// movimiento. Una pantalla de bloqueo que filtra la cifra que protege no
/// protege nada.
struct LockScreenView: View {

    @ObservedObject var lock: AppLock
    @Environment(\.colorScheme) private var scheme

    @State private var isWorking = false

    private var palette: Palette { Palette(scheme) }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                AppIconTile(size: 84, accent: AppBrand.accent, coinFace: .white, detail: true)

                VStack(spacing: 8) {
                    Text("AgruPay está bloqueada")
                        .font(.title2.bold())
                        .foregroundStyle(palette.label)

                    Text("Usa " + AppLock.biometryName + " para ver tus movimientos.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                if let error = lock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(palette.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                }

                Spacer()

                Button {
                    Task { await attempt() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: AppLock.biometryIcon)
                            .font(.title3)
                        Text("Desbloquear")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(AppBrand.accent, in: Capsule())
                }
                .disabled(isWorking)
                .opacity(isWorking ? 0.6 : 1)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        // Se pide la cara sola al aparecer: obligar a tocar un botón para que
        // salga el diálogo del sistema es un paso que no aporta nada.
        .task { await attempt() }
    }

    private func attempt() async {
        guard !isWorking else { return }
        isWorking = true
        await lock.unlock()
        isWorking = false
    }
}
