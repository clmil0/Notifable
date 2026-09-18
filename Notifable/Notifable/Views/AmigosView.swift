import SwiftUI
import SwiftData

/// 2c — el flujo completo de "Agregar amigo": código propio listo al abrir,
/// canjear el de un amigo con éxito animado, y la hoja se retira sola.
///
/// `onJoined` avisa a `AmigosHubView` quién se acaba de agregar para que la
/// fila en "Sin compartir" lo resalte — esta hoja no toca esa lista
/// directamente, sólo reporta el id.
struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Código de un enlace de invitación. Con él la hoja pregunta "¿Aceptar?"
    /// en vez de mostrar el formulario completo.
    var invitedCode: String? = nil
    let onJoined: (String) -> Void

    @State private var friendsManager = FriendsManager.shared
    @State private var dismissedInvite = false
    /// La página de invitación ya está publicada: se comparte con enlace.
    @State private var inviteLinkReady = InviteLinkCheck.isKnownReady

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    /// El guardado en el teléfono, si ya se consultó alguna vez: la hoja abre
    /// con el código puesto y "Compartir" listo, sin esperar a la red.
    @State private var myCode: String? = FriendsManager.shared.cachedFriendCode
    @State private var isGeneratingCode = false
    @State private var copied = false

    @State private var redeemInput = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var joinedFriend: Friend?

    private var isSuccess: Bool { joinedFriend != nil }

    var body: some View {
        VStack(spacing: 0) {
            if let joinedFriend {
                successContent(friend: joinedFriend)
            } else if let invitedCode, !dismissedInvite {
                inviteContent(code: invitedCode)
            } else {
                formContent
            }
        }
        .task { await ensureCode() }
        .task { inviteLinkReady = await InviteLinkCheck.isReady() }
        // Semimodal, no a pantalla completa: el contenido cabe de sobra en
        // media hoja, y abrirla hasta arriba era ocupar espacio de más.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .appAppearance()
        .appTextSize()
    }

    // MARK: - Formulario

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Agregar amigo")
                            .font(.title2.bold())
                        Text("Se agregan con un código, no por nombre.")
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundStyle(palette.secondaryLabel)
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                myCodeSection
                redeemSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
    }

    private var myCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TU CÓDIGO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)

            codeCells

            HStack(spacing: 10) {
                Button {
                    copyCode()
                } label: {
                    Text(copied ? "✓ Copiado" : "Copiar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(copied ? .green : themeColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(myCode == nil)

                if let myCode {
                    ShareLink(item: InviteLinks.shareText(code: myCode, linkReady: inviteLinkReady)) {
                        Text("Compartir")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(themeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                } else {
                    Text("Compartir")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(themeColor.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            privacyNote(text: "Agregarse **no comparte nada todavía**. Después eliges, por persona, si ve tu total del mes, algunas categorías, o nada.")
        }
    }

    private var codeCells: some View {
        let chars = Array(myCode ?? "")
        return HStack(spacing: 6) {
            if isGeneratingCode {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            } else if myCode == nil {
                Button("No se pudo generar el código. Reintentar.") {
                    Task { await ensureCode(force: true) }
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            } else {
                ForEach(0..<8, id: \.self) { i in
                    Text(i < chars.count ? String(chars[i]) : "")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .onTapGesture { copyCode() }
    }

    private var redeemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 6)

            Text("CANJEAR EL CÓDIGO DE UN AMIGO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)

            HStack(spacing: 10) {
                TextField("8 caracteres", text: $redeemInput)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(redeemError != nil ? Color.red : Color.clear, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: redeemInput) { _, newValue in
                        if newValue.count > 8 { redeemInput = String(newValue.prefix(8)) }
                        redeemError = nil
                    }

                Button {
                    submitRedeem()
                } label: {
                    if isRedeeming {
                        ProgressView().tint(.white)
                            .frame(width: 60, height: 48)
                    } else {
                        Text("Unirme")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .frame(height: 48)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSubmit ? .white : palette.tertiaryLabel)
                .background(canSubmit ? themeColor : Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(!canSubmit || isRedeeming)
            }

            if let redeemError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(redeemError)
                }
                .font(.caption)
                .foregroundStyle(.red)
            } else {
                Text("Escribe los 8 caracteres que te compartió tu amigo.")
                    .font(.caption)
                    .foregroundStyle(palette.tertiaryLabel)
            }
        }
    }

    private var canSubmit: Bool { redeemInput.count == 8 }

    private func privacyNote(text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("🔒")
                .font(.footnote)
            Text(.init(text))
                .font(.footnote)
                .foregroundStyle(themeColor)
                .tint(themeColor)
        }
        .padding(13)
        .background(themeColor.opacity(colorScheme == .dark ? 0.16 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Invitación recibida

    private func inviteContent(code: String) -> some View {
        let isOwn = code == myCode?.lowercased()
        let chars = Array(code)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Te invitaron a ser amigos")
                        .font(.title2.bold())
                    Text("Alguien te compartió su código de AgruPay.")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryLabel)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(palette.secondaryLabel)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(0..<chars.count, id: \.self) { i in
                    Text(String(chars[i]))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            if isOwn {
                Label("Es tu propio código: compártelo con alguien más.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            } else if let redeemError {
                Label(redeemError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                redeemInput = code
                submitRedeem()
            } label: {
                Group {
                    if isRedeeming {
                        ProgressView().tint(.white)
                    } else {
                        Text("Aceptar y agregar")
                            .font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isOwn ? Color(.systemGray4) : themeColor)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isOwn || isRedeeming)

            Button("Ahora no") { dismissedInvite = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
                .frame(maxWidth: .infinity)

            privacyNote(text: "Agregarse **no comparte nada todavía**. Después eliges, por persona, qué ve de tu gasto.")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 26)
    }

    // MARK: - Éxito

    private func successContent(friend: Friend) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 74, height: 74)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.green)
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))

            Text("Ya son amigos")
                .font(.title2.bold())

            Text("\(friend.displayName) está en tu lista. Todavía no ve nada de tu gasto.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isSuccess)
    }

    // MARK: - Acciones

    private func ensureCode(force: Bool = false) async {
        guard force || myCode == nil else { return }
        isGeneratingCode = true
        myCode = await friendsManager.myFriendCode()
        isGeneratingCode = false
    }

    private func copyCode() {
        guard let myCode else { return }
        UIPasteboard.general.string = myCode
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            copied = false
        }
    }

    private func submitRedeem() {
        guard canSubmit, !isRedeeming else { return }
        let code = redeemInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        isRedeeming = true
        redeemError = nil
        Task {
            let friend = await friendsManager.redeem(code: code)
            isRedeeming = false
            guard let friend else {
                redeemError = friendsManager.lastErrorMessage ?? "Código inválido. Revisa que esté bien escrito."
                return
            }
            onJoined(friend.id)
            joinedFriend = friend
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            dismiss()
        }
    }
}

/// 2a — "Tu perfil": pingüino, cabecera y datos en un solo lugar.
///
/// Vista previa arriba y controles abajo: se edita viendo el resultado, tal
/// como lo verán tus amigos. Nada se guarda hasta "Listo"; "Cerrar" descarta.
struct MyProfileSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false

    @State private var social = SocialProfileStore.shared
    @State private var auth = SupabaseAuthManager.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case penguin = "Pingüino", header = "Cabecera", data = "Datos"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .penguin
    @State private var nameDraft = ""
    @State private var statusDraft = ""
    @State private var bannerDraft = 0
    @State private var penguinDraft = PenguinLook()
    @State private var didLoad = false

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

                    Picker("Sección", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch tab {
                    case .penguin: penguinTab
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
                        Text("Tu perfil").font(.headline)
                        Button(action: shuffle) {
                            Text("🎲")
                        }
                        .accessibilityLabel("Sorpréndeme")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
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

    // MARK: - Pingüino

    private var penguinTab: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(spacing: 8) {
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
                carouselRow(title: "Accesorio",
                            value: penguinDraft.accessoryStyle.name,
                            index: penguinDraft.accessory, count: PenguinAccessory.allCases.count) { step in
                    penguinDraft.accessory = wrap(penguinDraft.accessory + step, PenguinAccessory.allCases.count)
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

            lockNote("Tu pingüino y tu cabecera se guardan en este teléfono y viajan en el respaldo. Tus amigos solo ven el resultado.")
        }
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
            }

            VStack(alignment: .trailing, spacing: 5) {
                field(title: "Estado") {
                    TextField("Ahorrando para el viaje a Cusco", text: $statusDraft, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...2)
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
        // Quien llega sin nombre (primera vez en Amigos) empieza por ahí.
        if social.displayName.isEmpty || social.displayName == "Amigo" { tab = .data }
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
