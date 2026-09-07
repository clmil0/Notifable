import SwiftUI

/// La puerta.
///
/// Dos pantallas en una. Lo que decide cuál se ve **no** es si hubo un fallo,
/// sino si hay algo que arreglar fuera de la app (ver `guidance`):
///
/// - **En reposo (2b)** — la biometría está configurada y funciona. Una sola
///   cosa que tocar: el sello a 96 pt con dos anillos que respiran mientras el
///   sistema busca, y el texto en una línea. Aquí caen también los tropiezos
///   que no hay que explicar —cancelar el diálogo, o que no te reconozca—:
///   lo único que hay que hacer es volver a mirar el teléfono, y el sello ya
///   dice "Toca para entrar". Si iOS no muestra nada —pasa— tocarlo vuelve a
///   pedirlo, que es lo que el usuario intentaría igual.
/// - **Guiada (1b)** — hace falta configurar o desbloquear algo: sin Face ID,
///   sin permiso, bloqueado por intentos, o sin código en el iPhone. El motivo
///   es el titular, los pasos numerados dicen cómo salir y el botón primario es
///   la acción que de verdad desbloquea. Un mensaje de error no es una salida:
///   "Face ID quedó bloqueado" deja al dueño mirando sus datos desde fuera sin
///   saber que se arregla desbloqueando el iPhone con su código.
///
/// No enseña **nada** del contenido: ni el total del mes, ni el último
/// movimiento. Una pantalla de bloqueo que filtra la cifra que protege no
/// protege nada.
struct LockScreenView: View {

    @ObservedObject var lock: AppLock
    @Environment(\.colorScheme) private var scheme

    @State private var isWorking = false
    /// `true` mientras se espera al sistema. Al agotarse, el sello deja de
    /// respirar y el texto pasa a "Toca para entrar": si iOS no llegó a mostrar
    /// nada, seguir animando sería mentir sobre lo que está pasando.
    @State private var isScanning = true
    @State private var scanTimer: Task<Void, Never>?

    private var palette: Palette { Palette(scheme) }

    /// Cuál de las dos pantallas toca, y con qué motivo.
    ///
    /// `nil` = la de reposo (2b). Un valor = la guiada (1b).
    ///
    /// Dos reglas, y en este orden:
    ///
    /// 1. Un fallo sólo lleva a 1b si `needsGuidance`: cancelar o no ser
    ///    reconocido son tropiezos con la biometría **ya configurada**, y ahí lo
    ///    único que hay que hacer es volver a mirar el teléfono. Antes cualquier
    ///    fallo saltaba a la pantalla guiada, así que cerrar el diálogo de Face
    ///    ID sacaba tres pasos y dos botones para decir "vuelve a intentarlo".
    /// 2. Sin biometría disponible no se pasa por 2b **en ningún momento**: esa
    ///    pantalla dice "Mira tu iPhone" junto a un sello de Face ID, y sin Face
    ///    ID configurado señala un sensor que no va a mirar nada. Se entra
    ///    directo a la pantalla guiada, sin el parpadeo de 2b que había mientras
    ///    el sistema devolvía el error.
    private var guidance: AppLockFailure? {
        if let failure = lock.lastFailure {
            return failure.needsGuidance ? failure : nil
        }
        guard AppLock.biometry == .none else { return nil }
        // Todavía no se ha intentado nada, así que el motivo exacto lo dirá el
        // sistema; esta es la mejor conjetura hasta que llegue.
        return AppLock.canLock ? .notEnrolled : .noPasscode
    }

    var body: some View {
        let guidance = self.guidance

        return ZStack {
            palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if let guidance {
                    failureBody(guidance)
                } else {
                    idleBody
                }

                footer(guidance)
            }
        }
        // Se pide la cara sola al aparecer: obligar a tocar un botón para que
        // salga el diálogo del sistema es un paso que no aporta nada.
        .task { await attempt() }
        .onDisappear { scanTimer?.cancel() }
        .animation(.snappy, value: lock.lastFailure)
        .animation(.snappy, value: isScanning)
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(spacing: 9) {
            AppIconTile(size: 30, accent: AppBrand.accent, coinFace: .white, detail: false)
            Text("AgruPay")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }

    // MARK: - 2b · en reposo

    private var idleBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            Button {
                Task { await attempt() }
            } label: {
                ZStack {
                    if isScanning {
                        breathingRing(delay: 0)
                        breathingRing(delay: 0.7)
                    }
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(palette.surface)
                        .frame(width: 96, height: 96)
                        .shadow(color: AppBrand.accent.opacity(0.16), radius: 16, y: 3)
                        .overlay(
                            Image(systemName: AppLock.biometryIcon)
                                .font(.system(size: 46, weight: .light))
                                .foregroundStyle(AppBrand.accent)
                        )
                }
                .frame(width: 96, height: 96)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            Text(isScanning ? "Mira tu iPhone" : "Toca para entrar")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(palette.label)
                .padding(.top, 28)

            Text(idleSubtitle)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.top, 8)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Mientras se busca, para qué sirve la cara. Al agotarse, **qué pasó**:
    /// un "no respondió" genérico después de cancelar a propósito suena a
    /// avería del teléfono cuando fue una decisión del usuario.
    private var idleSubtitle: String {
        if isScanning {
            return "\(AppLock.biometryName) abre tus movimientos, deudas y sueldo."
        }
        if let failure = lock.lastFailure, !failure.needsGuidance {
            return failure.idleSubtitle
        }
        return "\(AppLock.biometryName) no respondió. Toca el sello y vuelve a mirar."
    }

    /// Los anillos: nacen pegados al sello y se van abriendo hasta desaparecer.
    private func breathingRing(delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(AppBrand.accent, lineWidth: 2)
            .frame(width: 96, height: 96)
            .scaleEffect(isScanning ? 1.45 : 1)
            .opacity(isScanning ? 0 : 0.55)
            .animation(.easeOut(duration: 2.1).repeatForever(autoreverses: false).delay(delay),
                       value: isScanning)
    }

    // MARK: - 1b · tras un fallo

    private func failureBody(_ failure: AppLockFailure) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint(failure.tone).opacity(0.16))
                        .frame(width: 58, height: 58)
                    Image(systemName: failure.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(tint(failure.tone))
                }

                Text(failure.headline)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.label)
                    .multilineTextAlignment(.center)

                Text(failure.body)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Los pasos son lo que convierte el aviso en una salida.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(failure.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(palette.secondaryLabel)
                                .frame(width: 20, height: 20)
                                .background(palette.track, in: Circle())
                            Text(step)
                                .font(.footnote)
                                .foregroundStyle(palette.label)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tint(_ tone: AppLockFailure.Tone) -> Color {
        switch tone {
        case .neutral: return palette.secondaryLabel
        case .warning: return palette.warning
        case .error: return palette.negative
        }
    }

    // MARK: - Pie

    private func footer(_ guidance: AppLockFailure?) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                Text("Tus movimientos siguen cifrados en el iPhone.")
                    .font(.caption)
            }
            .foregroundStyle(palette.tertiaryLabel)

            if let failure = guidance {
                let primary = failure.primary
                filledButton(primary.label) { run(primary.action) }
                if let secondary = failure.secondary {
                    Button(secondary.label) { run(secondary.action) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                        .disabled(isWorking)
                }
            } else {
                // En reposo el único botón es la salida, no la acción: la
                // acción es mirar el teléfono, y ya está ocurriendo.
                outlinedButton("Usar código del iPhone") { run(.usePasscode) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 46)
    }

    private func filledButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(.white) }
                Text(isWorking ? "Verificando…" : title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(AppBrand.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    private func outlinedButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppBrand.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }

    // MARK: - Acciones

    private func run(_ action: AppLockFailure.Action) {
        switch action {
        case .retryBiometrics:
            Task { await attempt() }
        case .usePasscode:
            Task { await attempt(preferPasscode: true) }
        case .openSettings:
            lock.openSystemSettings()
        case .turnOffLock:
            lock.disableBecauseNoPasscode()
        }
    }

    private func attempt(preferPasscode: Bool = false) async {
        guard !isWorking else { return }
        isWorking = true
        startScanning()
        await lock.unlock(preferPasscode: preferPasscode)
        isWorking = false
        if lock.lastFailure != nil { stopScanning() }
    }

    private func startScanning() {
        scanTimer?.cancel()
        isScanning = true
        scanTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            guard !Task.isCancelled else { return }
            isScanning = false
        }
    }

    private func stopScanning() {
        scanTimer?.cancel()
        isScanning = false
    }
}
