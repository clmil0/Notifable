import SwiftUI
import SwiftData

/// 2a — "Agregar amigo": crear una invitación de un solo uso y usar la de
/// alguien (diseño `Amigos Rediseño.dc.html`).
///
/// Compartir manda: el código queda replegado, porque el mensaje que se
/// comparte ya lleva el enlace; sólo se despliega para dictarlo. Usar una
/// invitación no crea la amistad: manda una solicitud que la otra persona
/// acepta (ver `agrupay_friends_v9_private_invites.sql`).
struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    /// Token de un enlace de invitación (2e). Con él la hoja pregunta si
    /// mandar la solicitud en vez de mostrar el formulario completo.
    var invitedCode: String? = nil
    /// «Invitar» y «Usar invitación» abren hojas distintas: juntas en una
    /// sola, cada una estorbaba a la otra.
    enum Mode { case invite, redeem }
    var mode: Mode = .invite

    @State private var friendsManager = FriendsManager.shared
    @State private var dismissedInvite = false
    /// La página de invitación ya está publicada: se comparte con enlace.
    @State private var inviteLinkReady = InviteLinkCheck.isKnownReady

    @State private var invite: FriendInvite?
    @State private var isCreatingInvite = false
    @State private var createFailure: FriendsManager.InviteCreateFailure?
    @State private var showsCode = false
    @State private var copied = false
    @State private var confirmRevoke = false

    @State private var redeemInput = ""
    @State private var isRedeeming = false
    @State private var outcome: InviteRedeemOutcome?

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let invitedCode, !dismissedInvite {
                    inviteArrival(code: invitedCode)
                } else {
                    form
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .task { inviteLinkReady = await InviteLinkCheck.isReady() }
        .task { if invitedCode == nil, mode == .invite { await createInvite(reusingRecent: true) } }
        .confirmationDialog("¿Invalidar tus invitaciones abiertas?", isPresented: $confirmRevoke,
                            titleVisibility: .visible) {
            Button("Invalidar", role: .destructive) { Task { await revokeInvites() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Nadie podrá usarlas. Las solicitudes que ya te mandaron siguen esperando tu respuesta.")
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        // Opaca, como la del dictado: a media altura el sistema la dibujaría
        // translúcida.
        .presentationBackground(palette.surfaceElevated)
        .appAppearance()
        .appTextSize()
    }

    /// Hasta la mitad de la pantalla; lo que no quepa se desplaza dentro.
    private var detents: Set<PresentationDetent> {
        invitedCode != nil ? [.large] : [.medium]
    }

    // MARK: - Formulario (2a)

    @ViewBuilder
    private var form: some View {
        switch mode {
        case .invite: inviteForm
        case .redeem: redeemForm
        }
    }

    private var inviteForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "Invitar",
                   subtitle: "Con una invitación de un solo uso. Los dos tienen que aceptar.")
                .padding(.bottom, 18)

            inviteCard

            if let createFailure {
                failureCard(createFailure)
                    .padding(.top, 12)
            }

            lockNote(Text("Sirve **una sola vez**. Quien la use te manda una **solicitud**: no será tu amigo hasta que la aceptes, y agregarse **no comparte nada todavía**."))
                .padding(.top, 12)

            Button("Invalidar mis invitaciones abiertas") { confirmRevoke = true }
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 2)
        }
    }

    private var redeemForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "Usar una invitación",
                   subtitle: "Pega el enlace o el código que te mandaron.")
                .padding(.bottom, 18)

            redeemRow
            redeemFootnote
                .padding(.top, 8)

            if let outcome {
                outcomeCard(outcome)
                    .padding(.top, 14)
            }
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 23, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.label)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(width: 32, height: 32)
                    .background(palette.track, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
        }
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: invite == nil ? "ticket" : "checkmark.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(invite == nil ? palette.tertiaryLabel : palette.positive)
                    Text(invite == nil ? (isCreatingInvite ? "Preparando invitación…" : "Sin invitación todavía")
                                       : "Invitación lista")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.label)
                }
                Spacer(minLength: 8)
                if let invite {
                    // Cada 30 s: con minutos, un reloj quieto se ve roto.
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        chip(icon: "clock", text: "caduca en " + Self.timeLeft(invite.expiresAt))
                    }
                }
            }

            HStack(spacing: 10) {
                if let invite {
                    ShareLink(item: InviteLinks.shareText(token: invite.token, linkReady: inviteLinkReady)) {
                        bigLabel(icon: "square.and.arrow.up", title: "Compartir", filled: true)
                    }
                } else {
                    Button { Task { await createInvite() } } label: {
                        Group {
                            if isCreatingInvite {
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .background(accent.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            } else {
                                bigLabel(icon: "person.badge.plus", title: "Crear invitación", filled: true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreatingInvite)
                }

                Button(action: copyInvite) {
                    bigLabel(icon: copied ? "checkmark" : "doc.on.doc", title: copied ? "Copiado" : "Copiar",
                             filled: false)
                }
                .buttonStyle(.plain)
                .frame(width: 110)
                .disabled(invite == nil)
                .opacity(invite == nil ? 0.5 : 1)
            }
            .padding(.top, 12)

            Text("El mensaje que se comparte ya lleva el enlace.")
                .font(.system(size: 12))
                .foregroundStyle(palette.tertiaryLabel)
                .padding(.top, 9)

            Rectangle().fill(palette.hairline).frame(height: 0.5)
                .padding(.top, 12)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showsCode.toggle() }
            } label: {
                HStack {
                    Text("Ver el código para dictarlo")
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.secondaryLabel)
                    Spacer()
                    Image(systemName: showsCode ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.tertiaryLabel)
                }
                .padding(.top, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(invite == nil)

            if showsCode, let invite {
                Text(invite.grouped)
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .fontDesign(.monospaced)
                    .tracking(0.5)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(palette.label)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.hairline, lineWidth: 0.5))
                    .textSelection(.enabled)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(palette.label.opacity(0.12), lineWidth: 0.5))
    }

    private var redeemRow: some View {
        HStack(spacing: 10) {
            TextField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $redeemInput)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .fontDesign(.monospaced)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.hairline, lineWidth: 0.5))
                .onChange(of: redeemInput) { _, newValue in
                    if newValue.count > 30 { redeemInput = String(newValue.prefix(30)) }
                    if outcome?.isSuccess == false { outcome = nil }
                }
                .onSubmit { submitRedeem(redeemInput) }

            Button { submitRedeem(redeemInput) } label: {
                Group {
                    if isRedeeming {
                        ProgressView().tint(.white)
                    } else {
                        Text("Enviar")
                            .font(.system(size: 15.5, weight: .semibold))
                    }
                }
                .foregroundStyle(canSubmit ? Color.white : palette.tertiaryLabel)
                .frame(width: 92, height: 50)
                .background(canSubmit ? accent.color : palette.track,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isRedeeming)
        }
    }

    /// Cuántos caracteres faltan, o la regla, mientras no esté completo.
    private var redeemFootnote: some View {
        let typed = redeemInput.filter { $0.isLetter || $0.isNumber }.count
        let missing = InviteLinks.tokenLength - typed
        let text = (typed > 0 && missing > 0)
            ? "Faltan \(missing) caracteres. La O y el 0 valen igual, y los guiones son opcionales."
            : "20 caracteres. Da igual si escribes guiones, minúsculas o confundes la O con el 0."
        return Text(text)
            .font(.system(size: 12))
            .foregroundStyle(palette.tertiaryLabel)
    }

    private var canSubmit: Bool { InviteLinks.normalizedCode(redeemInput) != nil }

    // MARK: - Llegada por enlace (2e)

    private func inviteArrival(code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "Te invitaron", subtitle: "Alguien te mandó una invitación de AgruPay.")

            HStack(spacing: 14) {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.tertiaryLabel)
                    .frame(width: 56, height: 56)
                    .background(palette.track, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sabrás quién es al enviar la solicitud")
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(palette.secondaryLabel)
                    Text("Sin canjear, el servidor no revela a nadie.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.hairline, lineWidth: 0.5))
            .padding(.top, 22)

            Text(InviteLinks.grouped(code))
                .font(.system(size: 19, weight: .bold, design: .monospaced))
                .fontDesign(.monospaced)
                .tracking(0.5)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(palette.label)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.hairline, lineWidth: 0.5))
                .padding(.top, 12)

            if let outcome {
                outcomeCard(outcome)
                    .padding(.top, 14)
            }

            Button { submitRedeem(code) } label: {
                Group {
                    if isRedeeming {
                        ProgressView().tint(.white)
                    } else {
                        Text("Enviar solicitud")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRedeeming || outcome?.isSuccess == true)
            .padding(.top, 16)

            Button("Ahora no") { dismissedInvite = true; outcome = nil }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)

            lockNote(Text("Serán amigos cuando quien te invitó acepte tu solicitud. Agregarse **no comparte nada todavía**."))
        }
    }

    // MARK: - Resultados y errores (2f)

    private func outcomeCard(_ outcome: InviteRedeemOutcome) -> some View {
        switch outcome {
        case .sent(let name):
            return statusCard(icon: "checkmark.circle", tint: palette.positive, titleTint: palette.label,
                              title: "Solicitud enviada a \(name)",
                              message: "Cuando la acepte, aparecerá en tu lista.")
        case .alreadyFriends(let name):
            return statusCard(icon: "person.2", tint: palette.positive, titleTint: palette.label,
                              title: "Ya son amigos",
                              message: "\(name) ya está en tu lista. Todavía no ve nada de tu gasto.")
        case .invalid:
            return statusCard(icon: "exclamationmark.circle", tint: palette.negative,
                              title: "Esta invitación no sirve",
                              message: "Pídele una nueva a quien te invitó.")
        case .rateLimited:
            return statusCard(icon: "timer", tint: palette.warning,
                              title: "Demasiados intentos",
                              message: "Prueba de nuevo en una hora.")
        case .failed:
            return statusCard(icon: "wifi.slash", tint: palette.secondaryLabel, titleTint: palette.label,
                              title: "Sin conexión",
                              message: "No se pudo enviar la solicitud.")
        }
    }

    private func failureCard(_ failure: FriendsManager.InviteCreateFailure) -> some View {
        switch failure {
        case .offline:
            return statusCard(icon: "wifi.slash", tint: palette.secondaryLabel, titleTint: palette.label,
                              title: "Sin conexión",
                              message: "No se pudo crear la invitación.",
                              action: ("Reintentar", { Task { await createInvite() } }))
        case .tooMany:
            return statusCard(icon: "nosign", tint: palette.warning,
                              title: "Demasiadas invitaciones abiertas",
                              message: "Invalida las que ya mandaste y crea una nueva.",
                              action: ("Invalidar mis invitaciones abiertas", { confirmRevoke = true }))
        }
    }

    private func statusCard(icon: String, tint: Color, titleTint: Color? = nil,
                            title: String, message: String,
                            action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(titleTint ?? tint)
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
                if let action {
                    Button(action.0, action: action.1)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(accent.onSurface(scheme))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(palette.surface, in: Capsule())
                        .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(titleTint == nil ? tint.opacity(0.3) : palette.label.opacity(0.12), lineWidth: 1))
    }

    // MARK: - Piezas

    private func bigLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Color.white : accent.onSurface(scheme))
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(filled ? AnyShapeStyle(accent.color) : AnyShapeStyle(palette.surface),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(filled ? Color.clear : palette.hairline, lineWidth: 0.5))
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(accent.onSurface(scheme))
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(accent.color.opacity(0.12), in: Capsule())
    }

    private func lockNote(_ text: Text) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 2)
            text
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(accent.onSurface(scheme))
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.color.opacity(scheme == .dark ? 0.16 : 0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// «71 h 59 min»; en la última hora, sólo los minutos.
    private static func timeLeft(_ date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSinceNow / 60).rounded(.down)))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    // MARK: - Acciones

    private func createInvite(reusingRecent: Bool = false) async {
        guard !isCreatingInvite else { return }
        isCreatingInvite = true
        createFailure = nil
        let result = reusingRecent ? await friendsManager.inviteForSharing()
                                   : await friendsManager.createInvite()
        switch result {
        case .success(let created): invite = created
        case .failure(let failure): createFailure = failure
        }
        isCreatingInvite = false
    }

    private func revokeInvites() async {
        await friendsManager.revokeInvites()
        invite = nil
        showsCode = false
        await createInvite()
    }

    private func copyInvite() {
        guard let invite else { return }
        UIPasteboard.general.string = invite.grouped
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            withAnimation { copied = false }
        }
    }

    private func submitRedeem(_ raw: String) {
        guard let token = InviteLinks.normalizedCode(raw), !isRedeeming else { return }
        isRedeeming = true
        Task {
            let result = await friendsManager.redeem(token: token)
            isRedeeming = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { outcome = result }
            guard result.isSuccess else { return }
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            dismiss()
        }
    }
}

private extension InviteRedeemOutcome {
    var isSuccess: Bool {
        switch self {
        case .sent, .alreadyFriends: return true
        default: return false
        }
    }
}

/// 2a — "Tu perfil": personaje, cabecera y datos en un solo lugar.
///
/// Vista previa arriba y controles abajo: se edita viendo el resultado, tal
/// como lo verán tus amigos. Nada se guarda hasta "Listo"; "Cerrar" descarta.
///
/// Desde Mi perfil cada fila abre sólo lo suyo (`section`): el avatar con
/// Personaje y Cabecera, y el apodo o el estado directo en su campo, con el
/// teclado ya abierto.
struct MyProfileSheet: View {

    enum Section: String, Identifiable {
        /// Personaje, cabecera y datos: la entrada general.
        case all
        /// Sólo Personaje y Cabecera.
        case avatar
        /// Sólo los datos, con el foco en el nombre.
        case name
        /// Sólo los datos, con el foco en el estado.
        case status
        var id: String { rawValue }
    }

    var section: Section = .all

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false

    @State private var social = SocialProfileStore.shared
    @State private var auth = SupabaseAuthManager.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case penguin = "Personaje", header = "Cabecera", data = "Datos"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .penguin
    @State private var nameDraft = ""
    @State private var statusDraft = ""
    @State private var bannerDraft = 0
    @State private var penguinDraft = PenguinLook()
    @State private var didLoad = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, status }

    private var tabs: [Tab] {
        switch section {
        case .all: return Tab.allCases
        case .avatar: return [.penguin, .header]
        case .name, .status: return [.data]
        }
    }

    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    private static let statusSuggestions = ["Ahorrando para el viaje a Cusco",
                                            "Mes tranquilo",
                                            "Sin gastos hormiga"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerPreview

                    if tabs.count > 1 {
                        Picker("Sección", selection: $tab) {
                            ForEach(tabs) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    switch tab {
                    case .penguin: characterTab
                    case .header: headerTab
                    case .data: dataTab
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if tabs.contains(.penguin) {
                            Button(action: shuffle) {
                                Text("🎲")
                            }
                            .accessibilityLabel("Sorpréndeme")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
            .task {
                // El foco sólo prende una vez que la hoja terminó de subir;
                // pedirlo antes no abre el teclado.
                guard let field = initialFocus else { return }
                try? await Task.sleep(for: .milliseconds(450))
                focus = field
            }
        }
    }

    private var title: String {
        switch section {
        case .all: return "Tu perfil"
        case .avatar: return "Tu avatar"
        case .name: return "Tu apodo"
        case .status: return "Tu estado"
        }
    }

    private var initialFocus: Field? {
        switch section {
        case .name: return .name
        case .status: return .status
        case .all, .avatar: return nil
        }
    }

    // MARK: - Vista previa

    private var headerPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            SocialBannerView(index: bannerDraft)
                .frame(height: 104)

            HStack(alignment: .bottom, spacing: 12) {
                PenguinAvatar(look: penguinDraft, size: 92, background: palette.surface)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .animation(.spring(duration: 0.3), value: penguinDraft)

                VStack(alignment: .leading, spacing: 2) {
                    Text(nameDraft.isEmpty ? "Tu nombre" : nameDraft)
                        .font(.title3.bold())
                        .foregroundStyle(nameDraft.isEmpty ? palette.tertiaryLabel : palette.label)
                        .lineLimit(1)
                    Text("Así te verán tus amigos")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                }
                .padding(.bottom, 4)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .offset(y: -38)
            .padding(.bottom, -38 + 12)
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Personaje

    private var characterTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Especie")
                tileStrip {
                    speciesTile(nil)
                    ForEach(AvatarCatalog.animals) { speciesTile($0.id) }
                }
            }

            VStack(spacing: 8) {
                if penguinDraft.isPenguin {
                    penguinRows
                } else {
                    animalRows
                }
            }

            ForEach(AvatarZone.allCases) { zone in
                VStack(alignment: .leading, spacing: 7) {
                    sectionLabel(zone.name)
                    tileStrip {
                        itemTile(nil, zone: zone)
                        ForEach(AvatarCatalog.items(in: zone)) { itemTile($0, zone: zone) }
                    }
                }
            }

            Button(action: shuffle) {
                Text("Sorpréndeme")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themeColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(themeColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(themeColor.opacity(0.22), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)

            lockNote("Tu personaje y tu cabecera se guardan en este teléfono y viajan en el respaldo. Tus amigos solo ven el resultado.")
        }
    }

    @ViewBuilder
    private var penguinRows: some View {
        carouselRow(title: "Raza",
                    value: penguinDraft.breedStyle.name,
                    index: penguinDraft.breed, count: PenguinBreed.all.count) { step in
            penguinDraft.setBreed(penguinDraft.breed + step)
        }
        carouselRow(title: "Edad",
                    value: PenguinLook.ageNames[penguinDraft.age],
                    index: penguinDraft.age, count: PenguinLook.ageNames.count) { step in
            penguinDraft.age = wrap(penguinDraft.age + step, PenguinLook.ageNames.count)
        }
        carouselRow(title: "Manto y aletas",
                    value: PenguinPalettes.coats[penguinDraft.coat].name,
                    swatch: penguinDraft.coatHex,
                    index: penguinDraft.coat, count: PenguinPalettes.coats.count) { step in
            penguinDraft.coat = wrap(penguinDraft.coat + step, PenguinPalettes.coats.count)
        }
        carouselRow(title: "Acento",
                    value: PenguinPalettes.accents[penguinDraft.accent].name,
                    swatch: penguinDraft.accentHex,
                    index: penguinDraft.accent, count: PenguinPalettes.accents.count) { step in
            penguinDraft.accent = wrap(penguinDraft.accent + step, PenguinPalettes.accents.count)
        }
        carouselRow(title: "Pico y patas",
                    value: PenguinPalettes.beaks[penguinDraft.beak].name,
                    swatch: penguinDraft.beakHex,
                    index: penguinDraft.beak, count: PenguinPalettes.beaks.count) { step in
            penguinDraft.beak = wrap(penguinDraft.beak + step, PenguinPalettes.beaks.count)
        }
    }

    @ViewBuilder
    private var animalRows: some View {
        carouselRow(title: "Pelo",
                    value: AvatarPalettes.fur[penguinDraft.fur].name,
                    swatch: penguinDraft.furHex,
                    index: penguinDraft.fur, count: AvatarPalettes.fur.count) { step in
            penguinDraft.fur = wrap(penguinDraft.fur + step, AvatarPalettes.fur.count)
        }
        carouselRow(title: "Detalles",
                    value: AvatarPalettes.mark[penguinDraft.mark].name,
                    swatch: penguinDraft.markHex,
                    index: penguinDraft.mark, count: AvatarPalettes.mark.count) { step in
            penguinDraft.mark = wrap(penguinDraft.mark + step, AvatarPalettes.mark.count)
        }
        carouselRow(title: "Nariz",
                    value: AvatarPalettes.nose[penguinDraft.nose].name,
                    swatch: penguinDraft.noseHex,
                    index: penguinDraft.nose, count: AvatarPalettes.nose.count) { step in
            penguinDraft.nose = wrap(penguinDraft.nose + step, AvatarPalettes.nose.count)
        }
    }

    private func tileStrip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Perezosa: cada miniatura es un dibujo vectorial completo, y
            // abrir el editor dibujaba las ~30 de golpe aunque no se vieran.
            LazyHStack(alignment: .top, spacing: 10) { content() }
                .padding(.horizontal, 3)
                .padding(.vertical, 3)
        }
        .padding(.horizontal, -3)
    }

    /// El pingüino (`nil`) con su raza y colores de ahora; cada animal, con
    /// los suyos de diseño. Sin objetos: aquí se elige la silueta.
    private func speciesTile(_ id: String?) -> some View {
        var preview = penguinDraft
        if id != nil || !penguinDraft.isPenguin { preview.setSpecies(id) }
        preview.items = []
        let selected = penguinDraft.species == id
        return tile(look: preview,
                    title: id == nil ? "Pingüino" : preview.speciesName,
                    selected: selected) {
            guard !selected else { return }
            penguinDraft.setSpecies(id)
        }
    }

    /// Tu personaje tal como está, probándose `item` en su zona.
    private func itemTile(_ item: AvatarItem?, zone: AvatarZone) -> some View {
        let selected = penguinDraft.item(in: zone)?.id == item?.id
        var preview = penguinDraft
        preview.wear(item, in: zone)
        return tile(look: item == nil ? nil : preview,
                    title: item?.name ?? "Ninguno",
                    selected: selected) {
            penguinDraft.wear(item, in: zone)
        }
    }

    private func tile(look: PenguinLook?, title: String, selected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { action() }
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let look {
                        PenguinAvatar(look: look, size: 62, background: palette.surface)
                    } else {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(palette.tertiaryLabel)
                            .frame(width: 62, height: 62)
                            .background(palette.surface, in: Circle())
                    }
                }
                .overlay(
                    Circle()
                        .stroke(selected ? themeColor : palette.hairline, lineWidth: selected ? 2.5 : 0.5)
                        .padding(selected ? -2.5 : 0)
                )

                Text(title)
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.label : palette.secondaryLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func wrap(_ value: Int, _ count: Int) -> Int { ((value % count) + count) % count }

    private func carouselRow(title: String, value: String, swatch: String? = nil,
                             index: Int, count: Int, step: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            if let swatch {
                Circle()
                    .fill(RGBColor(hex: swatch).color)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.5))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(palette.tertiaryLabel)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            Text("\(index + 1) / \(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.tertiaryLabel)
            stepButton(systemName: "chevron.left", label: "Anterior \(title.lowercased())") { step(-1) }
            stepButton(systemName: "chevron.right", label: "Siguiente \(title.lowercased())") { step(1) }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private func stepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .foregroundStyle(themeColor)
                .frame(width: 30, height: 30)
                .background(palette.background, in: Circle())
                .overlay(Circle().stroke(palette.hairline, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func shuffle() {
        withAnimation(.spring(duration: 0.35)) {
            penguinDraft = .random()
            bannerDraft = Int.random(in: 0..<SocialBanner.allCases.count)
        }
    }

    // MARK: - Cabecera

    private var headerTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Cabecera")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 12) {
                ForEach(SocialBanner.allCases, id: \.rawValue) { banner in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { bannerDraft = banner.rawValue }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            SocialBannerView(banner)
                                .frame(height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(bannerDraft == banner.rawValue ? themeColor : palette.hairline,
                                                lineWidth: bannerDraft == banner.rawValue ? 2.5 : 0.5)
                                        .padding(bannerDraft == banner.rawValue ? -2.5 : 0)
                                )
                            Text(banner.name)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(bannerDraft == banner.rawValue ? .isSelected : [])
                }
            }
            lockNote("La cabecera es lo primero que ven tus amigos en tu tarjeta. No muestra ningún monto.")
        }
    }

    // MARK: - Datos

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            field(title: "Tu nombre") {
                TextField("Tu nombre", text: $nameDraft)
                    .font(.body)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .status }
            }

            VStack(alignment: .trailing, spacing: 5) {
                field(title: "Estado") {
                    TextField("Ahorrando para el viaje a Cusco", text: $statusDraft, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...2)
                        .focused($focus, equals: .status)
                        .onChange(of: statusDraft) { _, value in
                            if value.count > SocialProfileStore.statusLimit {
                                statusDraft = String(value.prefix(SocialProfileStore.statusLimit))
                            }
                        }
                }
                Text("\(statusDraft.count)/\(SocialProfileStore.statusLimit)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(palette.tertiaryLabel)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.statusSuggestions, id: \.self) { suggestion in
                        Button { statusDraft = suggestion } label: {
                            Text(suggestion)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.label)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(palette.track, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }

            lockNote("Tus amigos ven tu nombre, tu personaje, tu cabecera y tu estado. Nunca tus movimientos ni tus comercios.")
        }
    }

    // MARK: - Piezas

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.4)
            .foregroundStyle(palette.tertiaryLabel)
    }

    private func lockNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(palette.tertiaryLabel)
            Text(text)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel(title)
            content()
                .padding(13)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        nameDraft = social.displayName
        statusDraft = social.status
        bannerDraft = social.bannerIndex ?? 0
        penguinDraft = social.penguin
        tab = tabs[0]
        // Quien llega sin nombre (primera vez en Amigos) empieza por ahí.
        if section == .all, social.displayName.isEmpty || social.displayName == "Amigo" { tab = .data }
    }

    private func save() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = statusDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        social.bannerIndex = bannerDraft
        social.penguin = penguinDraft
        let emoji = social.avatarEmoji
        Task {
            await auth.updateProfile(name: name.isEmpty ? "Amigo" : name,
                                     status: status,
                                     avatarEmoji: emoji)
        }
        dismiss()
    }
}

/// 1d (sin cambios de diseño) — Editar amigo: apodo, color y avatar.
///
/// Nada de esto sale del teléfono: es cómo yo lo veo. Por eso la nota bajo el
/// apodo aclara que para él sigo siendo quien soy — un apodo no le renombra a
/// nadie del otro lado.
struct FriendEditSheet: View {

    let friend: Friend

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false

    @State private var social = SocialProfileStore.shared
    @State private var friendsManager = FriendsManager.shared

    @State private var nicknameDraft = ""
    @State private var colorIndex: Int = 0
    @State private var emojiDraft: String?
    @State private var didLoad = false
    @State private var showStopConfirm = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    private static let emojis = ["🌊", "🎬", "🥑", "🐕"]

    private var shownName: String {
        let trimmed = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? friend.displayName : trimmed
    }

    // El cuerpo va troceado a propósito: entero, el comprobador de tipos de
    // Swift se rinde ("unable to type-check this expression in reasonable
    // time") por los ternarios de color y tamaño dentro del árbol de vistas.
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    avatarHeader
                    nicknameField
                    colorRow
                    avatarRow

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(palette.negative)
                    }

                    destructiveActions
                }
                .padding(16)
            }
            .background(palette.background)
            .navigationTitle("Editar amigo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                }
            }
            .confirmationDialog("¿Dejar de compartir con " + shownName + "?",
                                isPresented: $showStopConfirm,
                                titleVisibility: .visible) {
                Button("Dejar de compartir", role: .destructive) {
                    Task {
                        await friendsManager.stopSharing(viewerID: friend.id)
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog("¿Eliminar a " + shownName + "?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Eliminar amigo", role: .destructive) { delete() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Dejarán de verse el gasto el uno al otro. Puedes volver a agregarlo con un código.")
            }
            .onAppear(perform: load)
        }
    }

    private var selectedColor: Color { SocialPalette.colors[colorIndex] }

    private var avatarHeader: some View {
        let usesEmoji = emojiDraft != nil
        let glyph = emojiDraft ?? SocialProfileStore.initial(of: shownName)
        return HStack {
            Spacer()
            VStack(spacing: 10) {
                Text(glyph)
                    .font(usesEmoji ? .system(size: 36) : .system(size: 32, weight: .bold))
                    .foregroundStyle(usesEmoji ? Color.primary : Color.white)
                    .frame(width: 78, height: 78)
                    .background(usesEmoji ? selectedColor.opacity(0.22) : selectedColor, in: Circle())
                Text(friend.displayName)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
            }
            Spacer()
        }
    }

    private var myName: String {
        let name = SocialProfileStore.shared.displayName
        return name.isEmpty ? "tu nombre" : name
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("APODO")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)

            TextField(friend.displayName, text: $nicknameDraft)
                .padding(12)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 0.5)
                )

            Text("Solo tú lo ves. Para \(friend.displayName) tú sigues siendo \(myName).")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
        }
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLOR")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)

            HStack(spacing: 12) {
                ForEach(SocialPalette.colors.indices, id: \.self) { index in
                    Button { colorIndex = index } label: {
                        Circle()
                            .fill(SocialPalette.colors[index])
                            .frame(width: 28, height: 28)
                            .overlay(ringOverlay(isSelected: colorIndex == index))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func ringOverlay(isSelected: Bool) -> some View {
        Circle()
            .stroke(palette.label, lineWidth: isSelected ? 2 : 0)
            .padding(-3)
    }

    private var avatarRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AVATAR")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)

            HStack(spacing: 10) {
                avatarChip(label: SocialProfileStore.initial(of: shownName), isSelected: emojiDraft == nil) {
                    emojiDraft = nil
                }
                ForEach(Self.emojis, id: \.self) { emoji in
                    avatarChip(label: emoji, isSelected: emojiDraft == emoji) { emojiDraft = emoji }
                }
            }
        }
    }

    @ViewBuilder
    private var destructiveActions: some View {
        VStack(spacing: 10) {
            if friendsManager.myShare(toward: friend.id) != nil {
                Button(role: .destructive) { showStopConfirm = true } label: {
                    Text("Dejar de compartir con " + shownName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.negative)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(palette.negative.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Text("Eliminar amigo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.negative)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.plain)
        }
    }

    private func avatarChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(palette.surface, in: Circle())
                .overlay(
                    Circle().stroke(isSelected ? SocialPalette.colors[colorIndex] : palette.hairline,
                                    lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let preferences = social.preferences(for: friend.id)
        nicknameDraft = preferences.nickname
        colorIndex = preferences.colorIndex ?? SocialPalette.defaultIndex(for: friend.id)
        emojiDraft = preferences.emoji
    }

    private func save() {
        social.update(friend.id) {
            $0.nickname = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.colorIndex = colorIndex
            $0.emoji = emojiDraft
        }
        dismiss()
    }

    private func delete() {
        Task {
            let removed = await friendsManager.removeFriend(friend.id)
            if removed {
                dismiss()
            } else {
                errorMessage = friendsManager.lastErrorMessage ?? "No se pudo eliminar la amistad."
            }
        }
    }
}

/// 2f — Perfil del amigo: su cabecera, la historia de la amistad, lo que te
/// comparte y lo que tú le compartes. De lectura — cambiar lo que le
/// compartes vive en `AmigoDetailView`, detrás de "Cambiar".
/// El detalle de un amigo (`5k`).
///
/// Dos bloques simétricos: lo que recibes arriba, lo que das abajo. La franja
/// del final resume en una frase exactamente qué ve el otro — la pregunta que
/// nadie quiere tener que deducir de dos interruptores y una lista.
struct FriendProfileView: View {
    let friend: Friend
    let totals: PeriodTotals
    /// Su fila de `friend_shares` hacia mí este mes, si ya la aceptaste.
    let incoming: FriendShareRow?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var friendsManager = FriendsManager.shared
    @State private var social = SocialProfileStore.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var showEditSheet = false
    @State private var showShareEditor = false
    @State private var showStopConfirm = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var shownName: String { social.name(for: friend.id, realName: friend.displayName) }
    private var myShare: FriendShareRow? { friendsManager.myShare(toward: friend.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if let incoming { theyShareSection(incoming) }

                    weShareSection

                    destructiveActions
                }
                .padding(16)
            }
            .background(palette.background)
            .navigationTitle(shownName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Editar") { showEditSheet = true }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                FriendEditSheet(friend: friend)
            }
            .sheet(isPresented: $showShareEditor) {
                AmigoDetailView(friend: friend, totals: totals)
            }
            .confirmationDialog("¿Dejar de compartir con " + shownName + "?",
                                isPresented: $showStopConfirm,
                                titleVisibility: .visible) {
                Button("Dejar de compartir", role: .destructive) {
                    Task {
                        await friendsManager.stopSharing(viewerID: friend.id)
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog("¿Eliminar a " + shownName + "?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Eliminar amigo", role: .destructive) { deleteFriend() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Dejarán de verse el gasto el uno al otro. Puedes volver a agregarlo con un código.")
            }
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(spacing: 8) {
            FriendAvatar(friend: friend, size: 76)

            Text(shownName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.label)

            if friend.hasNickname {
                Text(friend.displayName + " · apodo solo tuyo")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }

            if !friend.status.isEmpty {
                Text(friend.status)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.label)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(friend.tint.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lo que te comparte

    private func theyShareSection(_ incoming: FriendShareRow) -> some View {
        let maximum = incoming.categoryTotals.map(\.amount).max() ?? 0

        return VStack(spacing: 8) {
            ShellSectionHeader(title: "Lo que te comparte")

            ShellCard(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Total de " + Period.spanishMonthName(for: Date()).lowercased())
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondaryLabel)
                        Spacer()
                        Text("al " + updatedLabel(incoming))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.tertiaryLabel)
                    }

                    if let total = incoming.totalAmount, incoming.shareTotal {
                        Text(Money.format(total))
                            .font(.system(size: 30, weight: .bold))
                            .tracking(-0.8)
                            .foregroundStyle(palette.label)
                    }

                    ForEach(incoming.categoryTotals, id: \.name) { entry in
                        HStack(spacing: 10) {
                            Text(entry.name)
                                .font(.system(size: 13.5))
                                .foregroundStyle(palette.label)
                                .frame(width: 92, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(palette.track)
                                    Capsule()
                                        .fill(CategoryStyle.color(for: entry.name, accent: accent.color))
                                        .frame(width: max(4, geo.size.width * (maximum > 0 ? entry.amount / maximum : 0)))
                                }
                            }
                            .frame(height: 10)
                            Text(Money.formatCompact(entry.amount))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.label)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }

                    if !incoming.categoryTotals.isEmpty {
                        Text(incoming.categoryTotals.count == 1
                             ? "Comparte 1 de sus categorías."
                             : "Comparte \(incoming.categoryTotals.count) de sus categorías.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
        }
    }

    private func updatedLabel(_ row: FriendShareRow) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: row.updatedAt) ?? ISO8601DateFormatter().date(from: row.updatedAt) ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM"
        return f.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    // MARK: - Lo que tú le compartes

    /// El total se decide aquí mismo; las categorías, en su propia hoja. No
    /// hay «Movimientos sueltos»: el servidor sólo guarda totales por
    /// categoría, y ningún comercio ni fecha sale del teléfono.
    private var weShareSection: some View {
        VStack(spacing: 8) {
            ShellSectionHeader(title: "Lo que tú le compartes")

            MovementCard {
                Toggle(isOn: shareTotalBinding) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Total del mes").foregroundStyle(palette.label)
                        Text("El monto de Resumen, sin desglose")
                            .font(.caption).foregroundStyle(palette.secondaryLabel)
                    }
                }
                .tint(palette.positive)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.leading, 14)

                Button { showShareEditor = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Categorías elegidas").foregroundStyle(palette.label)
                            if let names = myShare?.shareCategories, !names.isEmpty {
                                Text(names.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(palette.secondaryLabel)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(myShare?.shareCategories.count ?? 0) de \(totals.byCategory.count)")
                            .foregroundStyle(palette.secondaryLabel)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            seesToday
        }
    }

    private var shareTotalBinding: Binding<Bool> {
        Binding(get: { myShare?.shareTotal ?? false }, set: { newValue in
            let categories = myShare?.shareCategories ?? []
            let amounts = totals.byCategory.map {
                FriendShareRow.CategoryAmount(name: $0.category, amount: $0.total)
            }
            Task {
                await friendsManager.setShare(viewerID: friend.id,
                                              shareTotal: newValue,
                                              categories: categories,
                                              totalAmount: totals.spent,
                                              categoryTotals: amounts)
            }
        })
    }

    /// «Mariana ve hoy: S/ 2,612 del mes, y Comida y Ocio con su monto.»
    private var seesToday: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent.onSurface(colorScheme))
            Text(seesTodayText)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(accent.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var seesTodayText: String {
        let shareTotal = myShare?.shareTotal ?? false
        let categories = myShare?.shareCategories ?? []
        let name = shownName

        func list(_ items: [String]) -> String {
            guard items.count > 1, let last = items.last else { return items.first ?? "" }
            return items.dropLast().joined(separator: ", ") + " y " + last
        }

        switch (shareTotal, categories.isEmpty) {
        case (false, true):
            return name + " no ve nada tuyo por ahora."
        case (true, true):
            return name + " ve hoy: " + Money.format(totals.spent) + " del mes, sin desglose."
        case (false, false):
            return name + " ve hoy: " + list(categories) + " con su monto, sin tu total."
        case (true, false):
            return name + " ve hoy: " + Money.format(totals.spent) + " del mes, y "
                + list(categories) + " con su monto."
        }
    }

    // MARK: - Acciones destructivas

    @ViewBuilder
    private var destructiveActions: some View {
        VStack(spacing: 4) {
            if myShare != nil {
                Button(role: .destructive) { showStopConfirm = true } label: {
                    Text("Dejar de compartir con " + shownName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.negative)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Text("Eliminar a " + shownName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.negative)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(palette.negative)
            }
        }
    }

    private func deleteFriend() {
        Task {
            let removed = await friendsManager.removeFriend(friend.id)
            if removed {
                dismiss()
            } else {
                errorMessage = friendsManager.lastErrorMessage ?? "No se pudo eliminar la amistad."
            }
        }
    }
}

/// 1e (sin cambios de diseño) — Qué le muestro a un amigo. Se abre desde
/// `FriendProfileView` al tocar "Cambiar" en "Lo que tú le compartes".
///
/// Las categorías salen de mis propios totales del periodo, no de lo que él ya
/// ve: marcar o desmarcar tiene que ser inmediato y no depender de una segunda
/// llamada de red. Lo que no está marcado nunca sale del teléfono.
struct AmigoDetailView: View {
    let friend: Friend
    let totals: PeriodTotals

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var friendsManager = FriendsManager.shared
    @State private var social = SocialProfileStore.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var shareTotal = false
    @State private var selectedCategories: Set<String> = []
    @State private var didLoadInitialState = false
    @State private var showStopConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false
    @State private var errorMessage: String?

    private var categoryTotals: [PeriodTotals.CategoryTotal] {
        totals.byCategory.filter { Money.cents($0.total) > 0 }
            .sorted { Money.cents($0.total) > Money.cents($1.total) }
    }

    private var shownName: String { social.name(for: friend.id, realName: friend.displayName) }
    private var stopConfirmTitle: String { "¿Dejar de compartir con " + shownName + "?" }
    private var deleteConfirmTitle: String { "¿Eliminar a " + shownName + "?" }

    /// Lo que vería si abriera la app ahora mismo.
    private var previewAmount: Double {
        if shareTotal { return totals.spent }
        return Money.sum(categoryTotals.filter { selectedCategories.contains($0.category) }) { $0.total }
    }

    private var isSharingAnything: Bool { shareTotal || !selectedCategories.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard
                    totalCard
                    categoriesCard
                    privacyNote

                    destructiveActions
                }
                .padding(16)
            }
            .background(palette.background)
            .navigationTitle("Compartir con " + shownName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Editar") { showEditSheet = true }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                FriendEditSheet(friend: friend)
            }
            .confirmationDialog(stopConfirmTitle,
                                isPresented: $showStopConfirm,
                                titleVisibility: .visible) {
                Button("Dejar de compartir", role: .destructive) {
                    Task {
                        await friendsManager.stopSharing(viewerID: friend.id)
                        dismiss()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog(deleteConfirmTitle,
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Eliminar amigo", role: .destructive) { deleteFriend() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Dejarán de verse el gasto el uno al otro. Puedes volver a agregarlo con un código.")
            }
            .onAppear(perform: loadInitialStateIfNeeded)
            .onChange(of: shareTotal) { _, _ in persistShare() }
            .onChange(of: selectedCategories) { _, _ in persistShare() }
        }
    }

    private var previewCard: some View {
        VStack(spacing: 6) {
            Text("VERÁ HOY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)
            Text(Money.format(isSharingAnything ? previewAmount : 0))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(palette.label)
            if !isSharingAnything {
                Text("Ahora mismo no ve nada tuyo")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .surfaceCard()
    }

    private var totalCard: some View {
        Toggle(isOn: $shareTotal) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total del mes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Text("El monto de Resumen, sin desglose")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
        }
        .tint(themeColor)
        .padding(14)
        .surfaceCard()
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Categorías elegidas")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Spacer()
                Text("\(selectedCategories.count) de \(categoryTotals.count)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
            .padding(14)

            ForEach(categoryTotals) { entry in
                Divider().background(palette.separator).padding(.leading, 46)
                Button {
                    toggleCategory(entry.category)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: CategoryStyle.icon(for: entry.category))
                            .font(.footnote)
                            .foregroundStyle(CategoryStyle.color(for: entry.category, accent: themeColor))
                            .frame(width: 22)
                        Text(entry.category)
                            .font(.subheadline)
                            .foregroundStyle(palette.label)
                        Spacer()
                        Text(Money.format(entry.total))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryLabel)
                        Image(systemName: selectedCategories.contains(entry.category) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedCategories.contains(entry.category) ? themeColor : palette.tertiaryLabel)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .surfaceCard()
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(palette.tertiaryLabel)
            Text("Solo lo que marques sale de tu teléfono. Nunca los comercios ni los movimientos.")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
            Spacer(minLength: 0)
        }
    }

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true
        // El servidor manda; el espejo local sólo entra cuando este mes todavía
        // no tiene fila —al estrenar teléfono tras restaurar el respaldo—.
        if let existing = friendsManager.myShare(toward: friend.id) {
            shareTotal = existing.shareTotal
            selectedCategories = Set(existing.shareCategories)
        } else {
            let remembered = social.preferences(for: friend.id)
            shareTotal = remembered.sharedTotal
            selectedCategories = Set(remembered.sharedCategories)
        }
    }

    private func toggleCategory(_ category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    private func persistShare() {
        guard didLoadInitialState else { return }
        let categoryAmounts = categoryTotals.map { FriendShareRow.CategoryAmount(name: $0.category, amount: $0.total) }
        Task {
            await friendsManager.setShare(viewerID: friend.id,
                                          shareTotal: shareTotal,
                                          categories: Array(selectedCategories),
                                          totalAmount: totals.spent,
                                          categoryTotals: categoryAmounts)
        }
    }

    /// Aparte del `body`, igual que en `FriendEditSheet`: junto con el resto
    /// de la vista, el comprobador de tipos de Swift se rendía aquí también
    /// ("unable to type-check this expression in reasonable time").
    @ViewBuilder
    private var destructiveActions: some View {
        if friendsManager.myShare(toward: friend.id) != nil {
            Button(role: .destructive) { showStopConfirm = true } label: {
                Text("Dejar de compartir con " + shownName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.negative)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(palette.negative.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }

        // Antes esto sólo vivía dentro de "Editar" — un paso de más para algo
        // que la gente busca desde aquí mismo.
        Button(role: .destructive) { showDeleteConfirm = true } label: {
            Text("Eliminar a " + shownName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.negative)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.plain)

        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(palette.negative)
        }
    }

    private func deleteFriend() {
        Task {
            let removed = await friendsManager.removeFriend(friend.id)
            if removed {
                dismiss()
            } else {
                errorMessage = friendsManager.lastErrorMessage ?? "No se pudo eliminar la amistad."
            }
        }
    }
}
