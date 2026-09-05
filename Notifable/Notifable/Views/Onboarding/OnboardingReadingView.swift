import SwiftUI

/// La primera lectura del correo, con su progreso a la vista.
///
/// Antes se entraba a la app en cuanto empezaba la lectura y el Resumen se
/// sentía trabado: SwiftData insertaba cientos de gastos mientras la lista
/// intentaba dibujarlos. No era lentitud de la app, era que se entraba
/// demasiado pronto. Esperar aquí convierte esos segundos en algo que se
/// entiende —y que se ve avanzar— en vez de en una app que va lenta.
///
/// No es una cárcel: en cuanto hay algo leído se puede entrar igual.
struct OnboardingReadingView: View {

    let monthsLabel: String
    let onDone: () -> Void

    @StateObject private var sync = GmailSyncService.shared
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }
    private var palette: Palette { Palette(scheme) }

    private var total: Int { max(sync.totalEmailsToProcess, 0) }
    private var done: Int { max(sync.emailsProcessed, 0) }
    private var ratio: Double {
        guard total > 0 else { return 0 }
        return min(Double(done) / Double(total), 1)
    }
    private var found: Int { sync.expensesFoundByBank.values.reduce(0, +) }
    private var isFinished: Bool { !sync.isSyncing && total > 0 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack {
                Circle()
                    .fill(accent.color.opacity(0.16))
                    .frame(width: 88, height: 88)
                Image(systemName: isFinished ? "checkmark" : "envelope.open.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(accent.onSurface(scheme))
                    .contentTransition(.symbolEffect(.replace))
            }

            Text(isFinished ? "Listo" : "Leyendo tus correos")
                .font(.title2.weight(.bold))
                .foregroundStyle(palette.label)
                .padding(.top, 20)

            Text(isFinished
                 ? "Ya tienes tu historial de \(monthsLabel) armado."
                 : "Estamos revisando los avisos de tu banco de \(monthsLabel). Tarda un momento y no hace falta que hagas nada.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 34)

            progress
                .padding(.top, 28)
                .padding(.horizontal, 26)

            if let error = sync.lastSyncError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(palette.negative)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 30)
            }

            Spacer(minLength: 20)

            buttons
                .padding(.bottom, 34)
        }
        .background(palette.background)
        // Si la lectura termina sola, no se deja al usuario mirando una
        // pantalla terminada: entra a la app.
        .onChange(of: isFinished) { _, finished in
            guard finished else { return }
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                onDone()
            }
        }
    }

    // MARK: - Progreso

    private var progress: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(accent.color)
                        .frame(width: geo.size.width * (total > 0 ? ratio : 0.12))
                        .animation(.easeOut(duration: 0.4), value: ratio)
                        // Sin total todavía: una barra corta que respira, para
                        // no fingir un progreso que no se conoce.
                        .opacity(total > 0 ? 1 : 0.5)
                }
            }
            .frame(height: 10)

            HStack {
                Text(total > 0 ? "\(done) de \(total) correos" : "Buscando correos…")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.secondaryLabel)
                Spacer()
                if found > 0 {
                    Text("\(found) gastos encontrados")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.positive)
                }
            }

            if !sync.expensesFoundByBank.isEmpty {
                HStack(spacing: 7) {
                    ForEach(sync.expensesFoundByBank.sorted(by: { $0.key < $1.key }), id: \.key) { bank, count in
                        Text("\(bank) \(count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.secondaryLabel)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(palette.track)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onDone) {
                Text(isFinished ? "Ver mis gastos" : "Entrar mientras termina")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFinished ? .white : accent.onSurface(scheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isFinished ? AnyShapeStyle(accent.color) : AnyShapeStyle(palette.surface))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isFinished ? .clear : palette.hairline, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            if !isFinished {
                Text("La lectura sigue en segundo plano.")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
            }
        }
        .padding(.horizontal, 24)
    }
}
