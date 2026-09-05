import SwiftUI
import SwiftData

/// Primera apertura de la app. Cinco pasos encadenados:
///
/// 1. **Carrusel** de tres pantallas que enseñan la UI real en pequeño —el
///    correo convirtiéndose en gasto, la barra de ritmo, la comparación con
///    amigos—. Cada una se anima al entrar: lo que hay que entender antes de
///    dar permiso sobre el correo es qué se gana a cambio, y verlo moverse lo
///    explica mejor que un párrafo.
/// 2. **Login**, con la comparación lado a lado. "Sin cuenta" no es un
///    callejón: es un modo de uso completo donde los gastos se anotan a mano.
/// 3. **Recuperar** — sólo si entró con Google y esa cuenta ya tenía respaldo.
/// 4. **Cuánto correo leer** — 1 M, 3 M, 6 M, 1 A u otro, o no leer nada.
/// 5. La app.
struct OnboardingView: View {

    /// Lo pone en `true` el último paso; `NotifableApp` deja de presentar esta
    /// pantalla a partir de ahí.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @Environment(\.colorScheme) private var scheme

    @StateObject private var gmailAuth = GmailAuthService.shared

    enum Step: Equatable {
        case slides
        case restore(BackupHeader)
        case history(usesGmail: Bool)
        case reading(monthsLabel: String)
    }

    @State private var step: Step = .slides
    @State private var page = 0
    @State private var isConnecting = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }
    private var palette: Palette { Palette(scheme) }

    private static let lastSlide = 2

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            switch step {
            case .slides:
                carousel
            case .restore(let header):
                OnboardingRestoreView(header: header) { restored in
                    advanceAfterAccount(restored: restored)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .history(let usesGmail):
                OnboardingHistoryView(usesGmail: usesGmail) { monthsLabel in
                    if let monthsLabel {
                        withAnimation(.snappy) { step = .reading(monthsLabel: monthsLabel) }
                    } else {
                        finish()
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .reading(let monthsLabel):
                OnboardingReadingView(monthsLabel: monthsLabel) { finish() }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: step)
        .onChange(of: gmailAuth.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated, isConnecting else { return }
            isConnecting = false
            Task { await lookForBackup() }
        }
    }

    // MARK: - Carrusel + login

    private var carousel: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                slideMail.tag(0)
                slidePace.tag(1)
                slideFriends.tag(2)
                loginPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                Spacer()
                if page <= Self.lastSlide {
                    Button("Saltar") { withAnimation(.snappy) { page = 3 } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if page <= Self.lastSlide { footer }
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                ForEach(0...Self.lastSlide, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? accent.color : palette.tertiaryLabel.opacity(0.45))
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.snappy, value: page)
                }
            }

            Button {
                withAnimation(.snappy) { page += 1 }
            } label: {
                Text(page == Self.lastSlide ? "Empezar" : "Siguiente")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(accent.color)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 28)
    }

    // MARK: - 1. El correo se convierte en gasto

    private var slideMail: some View {
        OnboardingSlide(
            isActive: page == 0,
            title: "Tus gastos se anotan solos",
            subtitle: "Vincula tu Gmail y AgruPay lee los avisos de tu banco. Y si pagaste algo que te van a devolver, lo marcas como por cobrar y no cuenta en tu mes.",
            footnote: (icon: "lock.fill",
                       text: "Solo lectura. No escribimos ni enviamos correos, y tus gastos se quedan en tu iPhone.")
        ) { beat in
            VStack(spacing: 14) {
                mailToExpense(
                    beat: beat, mailDelay: 0, rowDelay: 0.72, chipDelay: nil,
                    sender: "notificaciones@notificacionesbcp.com.pe",
                    time: "09:42",
                    subject: "Realizaste un consumo con tu Tarjeta de Crédito BCP",
                    icon: "cart.fill", tint: .orange,
                    merchant: "Plaza Vea",
                    detail: "Supermercado · hoy 09:42",
                    amount: "S/ 84.90",
                    receivable: nil)

                mailToExpense(
                    beat: beat, mailDelay: 1.15, rowDelay: 1.87, chipDelay: 2.5,
                    sender: "yape@yape.com.pe",
                    time: "21:04",
                    subject: "Constancia de Yapeo a JORGE M.",
                    icon: "fork.knife", tint: .purple,
                    merchant: "Cena · Jorge",
                    detail: "Te deben S/ 60.00 · no cuenta en tu mes",
                    amount: "S/ 120.00",
                    receivable: "POR COBRAR")

                bankStrip.reveal(beat, after: 2.8)
            }
        }
    }

    private func mailToExpense(beat: Double, mailDelay: Double, rowDelay: Double,
                               chipDelay: Double?,
                               sender: String, time: String, subject: String,
                               icon: String, tint: Color,
                               merchant: String, detail: String, amount: String,
                               receivable: String?) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(sender)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(time)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.tertiaryLabel)
                }
                Text(subject)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.track)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .reveal(beat, after: mailDelay)

            // El parpadeo es el momento en que la app hace su trabajo: aparece
            // entre el correo y el gasto, que es exactamente lo que cuenta.
            Label("REGISTRADO EN AGRUPAY", systemImage: "arrow.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.tertiaryLabel)
                .padding(.vertical, 5)
                .opacity(beat > mailDelay + 0.35 ? 1 : 0)
                .blink(active: beat > mailDelay + 0.35 && beat < rowDelay + 0.4)

            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 34, height: 34)
                    Image(systemName: icon).font(.system(size: 14)).foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(merchant)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.label)
                        if let receivable, let chipDelay {
                            Text(receivable)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.16))
                                .clipShape(Capsule())
                                .scaleEffect(beat >= chipDelay ? 1 : 0.84)
                                .opacity(beat >= chipDelay ? 1 : 0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.65),
                                           value: beat >= chipDelay)
                        }
                    }
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(amount)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.label)
            }
            .padding(10)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
            .reveal(beat, after: rowDelay, offset: 14)
        }
    }

    private var bankStrip: some View {
        HStack(spacing: 8) {
            ForEach(["BCP", "BBVA", "Interbank", "Scotiabank", "Yape"], id: \.self) { bank in
                Text(bank)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(palette.track)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 2)
    }

    // MARK: - 2. El ritmo del mes

    private var slidePace: some View {
        OnboardingSlide(
            isActive: page == 1,
            title: "Sabes si vas rápido antes de fin de mes",
            subtitle: "La línea blanca marca por dónde va el mes. Si el relleno la pasa, estás gastando más rápido de lo que avanza.",
            footnote: nil
        ) { beat in
            VStack(spacing: 12) {
                paceCard(beat: beat)
                pendingCard(icon: "tag.fill", tint: .orange,
                            title: "3 comercios sin clasificar",
                            detail: "S/ 214.00 sin categoría",
                            action: "Clasificar")
                    .reveal(beat, after: 1.35)
                pendingCard(icon: "clock.fill", tint: accent.color,
                            title: "2 gastos por confirmar",
                            detail: "S/ 89.90 que aún no cuentan en tu mes",
                            action: "Revisar")
                    .reveal(beat, after: 1.55)
            }
        }
    }

    private func paceCard(beat: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gastado en septiembre")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryLabel)
                Spacer()
                Text("quedan 18 días")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.tertiaryLabel)
            }

            Text("S/ 1,284.50")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(palette.label)
                .opacity(beat > 0.1 ? 1 : 0.25)
                .animation(.easeOut(duration: 0.9), value: beat > 0.1)

            // La barra crece de 0 a 64 % y cruza la marca del 40 %: ver el
            // adelantamiento es el argumento de la pantalla.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(accent.color)
                        .frame(width: geo.size.width * (beat > 0.05 ? 0.64 : 0))
                        .animation(.timingCurve(0.25, 0.9, 0.3, 1, duration: 1.4), value: beat > 0.05)
                    Capsule()
                        .fill(palette.label)
                        .frame(width: 2.5, height: 16)
                        .offset(x: geo.size.width * 0.40)
                }
            }
            .frame(height: 10)

            HStack {
                Text("por aquí va el mes")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.tertiaryLabel)
                Spacer()
                Text("Presupuesto S/ 2,000")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.tertiaryLabel)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.warning)
                (Text("Vas rápido. A este ritmo cierras el mes en ")
                 + Text("S/ 3,211").fontWeight(.semibold)
                 + Text("."))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(.top, 2)
            .reveal(beat, after: 1.1, offset: 6)
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
    }

    private func pendingCard(icon: String, tint: Color, title: String,
                             detail: String, action: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.label)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondaryLabel)
            }
            Spacer(minLength: 6)
            Text(action)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent.onSurface(scheme))
        }
        .padding(11)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - 3. Amigos

    private var slideFriends: some View {
        OnboardingSlide(
            isActive: page == 2,
            title: "Y si quieres, lo comparas con tus patas",
            subtitle: "Renzo comparte sus categorías, Mile solo su total. Tú decides qué muestras. Y lo que pagaste en efectivo lo agregas con el +.",
            footnote: (icon: "eye.slash.fill",
                       text: "Cada uno elige qué comparte: solo el total, o también sus categorías.")
        ) { beat in
            VStack(alignment: .leading, spacing: 12) {
                Text("SEPTIEMBRE · GASTO DEL MES")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.tertiaryLabel)

                friendRow(beat: beat, delay: 0.05, name: "Tú", amount: "S/ 1,284",
                          ratio: 0.76, tint: accent.color, note: nil)

                VStack(alignment: .leading, spacing: 8) {
                    friendRow(beat: beat, delay: 0.18, name: "Renzo", amount: "S/ 1,010",
                              ratio: 0.60, tint: .teal, note: "comparte categorías")
                    categoryChip("Transporte", "S/ 420", .blue).reveal(beat, after: 0.34, offset: 6)
                    categoryChip("Comida", "S/ 350", .orange).reveal(beat, after: 0.44, offset: 6)
                    categoryChip("Mercado", "S/ 240", .green).reveal(beat, after: 0.54, offset: 6)
                }

                friendRow(beat: beat, delay: 0.31, name: "Mile", amount: "S/ 1,690",
                          ratio: 1.0, tint: .pink, note: "solo su total")

                addButtonHint(beat: beat)
            }
            .padding(14)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
        }
    }

    private func friendRow(beat: Double, delay: Double, name: String, amount: String,
                           ratio: Double, tint: Color, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.label)
                if let note {
                    Text(note)
                        .font(.system(size: 9))
                        .foregroundStyle(palette.tertiaryLabel)
                }
                Spacer(minLength: 6)
                Text(amount)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.label)
            }
            // Las barras crecen desde la izquierda, escalonadas: se leen como
            // una comparación que se dibuja, no como tres datos ya puestos.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(tint)
                        .frame(width: geo.size.width * ratio)
                        .scaleEffect(x: beat >= delay ? 1 : 0, anchor: .leading)
                        .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 1.0), value: beat >= delay)
                }
            }
            .frame(height: 7)
        }
    }

    private func categoryChip(_ name: String, _ amount: String, _ tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryLabel)
            Spacer(minLength: 6)
            Text(amount)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.secondaryLabel)
        }
        .padding(.leading, 10)
    }

    private func addButtonHint(beat: Double) -> some View {
        HStack(spacing: 8) {
            ForEach([("Gasto", "arrow.up.right", Color.red),
                     ("Ingreso", "arrow.down.left", Color.green)], id: \.0) { item in
                HStack(spacing: 4) {
                    Image(systemName: item.1).font(.system(size: 9, weight: .bold))
                    Text(item.0).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(item.2)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(item.2.opacity(0.14))
                .clipShape(Capsule())
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(accent.color).frame(width: 28, height: 28)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(beat >= 0.9 ? 1 : 0.9)
            .animation(.spring(response: 0.45, dampingFraction: 0.55).repeatCount(2, autoreverses: true),
                       value: beat >= 0.9)
        }
        .padding(.top, 2)
        .reveal(beat, after: 0.72, offset: 8)
    }

    // MARK: - 4. La decisión

    private var loginPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image("app_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 44)

                Text("AgruPay")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.secondaryLabel)
                    .padding(.top, 10)

                Text("Deja que tus gastos se anoten solos")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.label)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                Text("Conecta tu correo y cada consumo queda registrado apenas llega el aviso de tu banco. Sin cuenta también funciona, anotándolos tú.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 28)

                comparison
                    .padding(.top, 22)
                    .padding(.horizontal, 20)

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.tertiaryLabel)
                    Text("Permiso de solo lectura sobre Gmail. Nunca escribimos, enviamos ni borramos correos.")
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                }
                .padding(.top, 14)
                .padding(.horizontal, 28)

                loginButtons
                    .padding(.top, 26)
                    .padding(.bottom, 34)
            }
        }
    }

    private var comparison: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Text("Con Google").frame(width: 74)
                Text("Sin cuenta").frame(width: 68)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.tertiaryLabel)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            comparisonRow("Lectura automática de gastos del correo", google: true, alone: false)
            comparisonRow("Respaldo en la nube", google: true, alone: false)
            comparisonRow("Sincronización entre dispositivos", google: true, alone: false)
            comparisonRow("Amigos y comparaciones", google: true, alone: false)
            comparisonRow("Presupuesto, categorías y recurrentes", google: true, alone: true, isLast: true)
        }
        .padding(.vertical, 12)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
    }

    private func comparisonRow(_ title: String, google: Bool, alone: Bool,
                               isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                mark(google).frame(width: 74)
                mark(alone).frame(width: 68)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !isLast {
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 12)
            }
        }
    }

    private func mark(_ available: Bool) -> some View {
        Image(systemName: available ? "checkmark.circle.fill" : "minus")
            .font(.system(size: available ? 15 : 12, weight: .semibold))
            .foregroundStyle(available ? palette.positive : palette.tertiaryLabel)
    }

    private var loginButtons: some View {
        VStack(spacing: 12) {
            Button {
                isConnecting = true
                GmailAuthService.shared.signIn()
            } label: {
                HStack(spacing: 10) {
                    if isConnecting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "envelope.fill").font(.system(size: 15))
                    }
                    Text(isConnecting ? "Conectando…" : "Continuar con Google")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            // Sin cuenta no hay correo que leer, así que la pantalla de "cuánto
            // leer" no tendría nada que ofrecer: se va directo a la app.
            Button("Continuar sin cuenta") { finish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Encadenado

    /// Entró con Google: antes de nada, ¿esa cuenta ya tenía un respaldo? Si no
    /// lo tiene —el caso normal de alguien que estrena la app— no se le enseña
    /// una pantalla de recuperación vacía.
    private func lookForBackup() async {
        let manager = ConfigBackupManager.shared
        if let header = await manager.peek(code: nil), header.hasData {
            manager.lastErrorMessage = nil
            withAnimation(.snappy) { step = .restore(header) }
        } else {
            manager.lastErrorMessage = nil
            await advanceAfterAccountAsync(restored: false)
        }
    }

    private func advanceAfterAccount(restored: Bool) {
        Task { await advanceAfterAccountAsync(restored: restored) }
    }

    private func advanceAfterAccountAsync(restored: Bool) async {
        // Si no restauró, la sincronización se enciende igual: es una cuenta
        // nueva y a partir de ahora lo que configure se guarda solo.
        if !restored {
            await ConfigBackupManager.shared.enableWithAccount()
        }
        ConfigBackupManager.shared.dismissBackupOffer()
        withAnimation(.snappy) { step = .history(usesGmail: true) }
    }

    private func finish() {
        hasSeenOnboarding = true
    }
}

// MARK: - Estructura común de las tres primeras

/// Ilustración arriba, título y texto abajo, con un "beat" que avanza mientras
/// la pantalla está visible.
///
/// El beat es el reloj de la animación: cada pieza se compara con él para saber
/// si le toca aparecer. Al salir de la pantalla vuelve a cero, así que la
/// animación se vuelve a ver si el usuario regresa deslizando.
private struct OnboardingSlide<Illustration: View>: View {

    let isActive: Bool
    let title: String
    let subtitle: String
    let footnote: (icon: String, text: String)?
    @ViewBuilder let illustration: (Double) -> Illustration

    @Environment(\.colorScheme) private var scheme
    @State private var beat: Double = 0
    @State private var ticker: Task<Void, Never>?

    private var palette: Palette { Palette(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            illustration(beat)
                .padding(.horizontal, 22)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.label)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: footnote.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.tertiaryLabel)
                        Text(footnote.text)
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 28)
            .frame(height: 190, alignment: .top)

            Spacer(minLength: 96)
        }
        .padding(.top, 44)
        .onAppear { if isActive { start() } }
        .onDisappear { stop() }
        .onChange(of: isActive) { _, active in active ? start() : stop() }
    }

    private func start() {
        stop()
        beat = 0
        ticker = Task { @MainActor in
            // 40 pasos de 100 ms: suficiente para escalonar sin gastar CPU.
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
                beat += 0.1
            }
        }
    }

    private func stop() {
        ticker?.cancel()
        ticker = nil
        beat = 0
    }
}

// MARK: - Piezas de animación

private extension View {

    /// Equivalente del `agpFadeUp` del diseño: aparece subiendo, cuando el beat
    /// pasa el retardo que le toca.
    func reveal(_ beat: Double, after delay: Double, offset: CGFloat = 12) -> some View {
        let shown = beat >= delay
        return self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : offset)
            .animation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.8), value: shown)
    }

    /// `agpBlink`: sólo mientras la app "está procesando" el correo.
    func blink(active: Bool) -> some View {
        modifier(BlinkModifier(active: active))
    }
}

private struct BlinkModifier: ViewModifier {
    let active: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (dim ? 0.35 : 1) : 1)
            .onChange(of: active) { _, isActive in
                guard isActive else { dim = false; return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}
