import SwiftUI
import SwiftData

/// Amigos: el hub del diseño `Social · Amigos.dc.html` (1a–1f).
///
/// A diferencia de `SocialView`/`SyncManager` (el PoC de "Ver actividad de la
/// comunidad" que sigue en Ajustes → Respaldo), aquí nunca sale un movimiento
/// ni un comercio del teléfono: sólo los totales que el propio usuario marcó,
/// por amigo, con permiso explícito y revocable en cualquier momento.
///
/// Lo que suma el rediseño sobre la versión anterior:
/// - una tarjeta de perfil arriba, con nombre y **estado** editables;
/// - **apodo, color y emoji** por amigo, privados de este teléfono
///   (`SocialProfileStore`), que viajan en el respaldo de configuración;
/// - lo que te comparten legible de un golpe, con su desglose;
/// - un contador de "con cuántos de tus amigos estás compartiendo".
struct AmigosHubView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var scrollOffset: CGFloat
    @Binding var scrollToTopTrigger: Bool

    @StateObject private var exchangeRateService = ExchangeRateService.shared
    @State private var friendsManager = FriendsManager.shared
    @State private var auth = SupabaseAuthManager.shared
    @State private var social = SocialProfileStore.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var didStartSession = false
    @State private var showProfileSheet = false

    @State private var showInviteSheet = false
    @State private var myInviteCode: String?
    @State private var isGeneratingCode = false
    @State private var redeemCodeDraft = ""
    @State private var isRedeeming = false
    @State private var redeemFeedback: String?

    @State private var selectedFriend: Friend?
    @State private var friendToEdit: Friend?

    /// El mismo `Period` que Resumen, Categorías y Ritmo — el mes actual.
    private var period: Period { Period(granularity: .mes, reference: Date()) }

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses,
                          incomes: [],
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate)
    }

    /// "2 de 4 amigos": con cuántos estoy compartiendo algo ahora mismo.
    private var sharingCount: Int {
        friendsManager.friends.filter { isSharing(with: $0) }.count
    }

    private func isSharing(with friend: Friend) -> Bool {
        guard let share = friendsManager.myShare(toward: friend.id) else { return false }
        return share.shareTotal || !share.shareCategories.isEmpty
    }

    var body: some View {
        TrackableScrollView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 22) {
                header
                profileCard

                if !auth.isReady {
                    loadingCard
                } else if friendsManager.friends.isEmpty && friendsManager.acceptedIncoming.isEmpty {
                    emptyState
                } else {
                    if !friendsManager.pendingIncoming.isEmpty {
                        pendingIncomingSection
                    }
                    if !friendsManager.acceptedIncoming.isEmpty {
                        incomingSection
                    }
                    outgoingSection
                    inviteCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .task {
            guard !didStartSession else { return }
            didStartSession = true
            let ready = await auth.ensureSession(defaultName: social.displayName.isEmpty ? "Amigo" : social.displayName)
            if ready, social.displayName.isEmpty || social.displayName == "Amigo" {
                showProfileSheet = true
            }
            await friendsManager.refresh()
        }
        .refreshable { await friendsManager.refresh() }
        .sheet(isPresented: $showProfileSheet) {
            MyProfileSheet()
        }
        .sheet(isPresented: $showInviteSheet) { inviteSheet }
        .sheet(item: $selectedFriend) { friend in
            AmigoDetailView(friend: friend, totals: totals)
        }
        .sheet(item: $friendToEdit) { friend in
            FriendEditSheet(friend: friend)
        }
    }

    // MARK: - Encabezado y perfil

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Amigos")
                .font(.largeTitle.bold())
            Spacer()
            Text(Period.spanishMonthName(for: Date()))
                .font(.subheadline)
                .foregroundStyle(palette.secondaryLabel)
        }
        .padding(.top, 8)
    }

    /// 1c en pequeño: quién soy para mis amigos. El estado va aquí y no en
    /// Ajustes porque es lo único que ellos ven además del nombre.
    private var profileCard: some View {
        HStack(spacing: 12) {
            avatar(glyph: social.avatarEmoji ?? SocialProfileStore.initial(of: social.displayName),
                   tint: themeColor,
                   size: 46,
                   isEmoji: social.avatarEmoji != nil)

            VStack(alignment: .leading, spacing: 3) {
                Text(social.displayName.isEmpty ? "Tu nombre" : social.displayName)
                    .font(.headline)
                    .foregroundStyle(palette.label)
                Text(social.status.isEmpty ? "Añade tu estado" : social.status)
                    .font(.footnote)
                    .foregroundStyle(social.status.isEmpty ? palette.tertiaryLabel : palette.secondaryLabel)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button("Editar") { showProfileSheet = true }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(themeColor)
        }
        .padding(14)
        .surfaceCard()
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Conectando…")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .surfaceCard()
    }

    /// 1f: sin amigos, lo que hace falta no es una lista vacía sino saber qué
    /// se gana y cómo empezar.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 30))
                .foregroundStyle(themeColor)
                .frame(width: 74, height: 74)
                .background(themeColor.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Circle())

            Text("Todavía nadie ve tu gasto")
                .font(.title3.bold())
                .foregroundStyle(palette.label)

            Text("Agrega a un amigo y elige, por persona, si ve tu total del mes, algunas categorías, o nada.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Button {
                showInviteSheet = true
            } label: {
                Text("Agregar un amigo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(themeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button("Tengo un código") { showInviteSheet = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .surfaceCard()
    }

    // MARK: - Te quieren compartir

    private var pendingIncomingSection: some View {
        VStack(spacing: 10) {
            ForEach(friendsManager.pendingIncoming) { row in
                HStack(spacing: 12) {
                    friendAvatar(id: row.sharerID, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(friendsManager.displayName(for: row.sharerID))
                            .font(.subheadline.bold())
                            .foregroundStyle(palette.label)
                        Text("Quiere compartirte su gasto del mes")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }

                    Spacer(minLength: 4)

                    Button {
                        Task { await friendsManager.ignore(sharerID: row.sharerID) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(palette.secondaryLabel)
                            .frame(width: 32, height: 32)
                            .background(palette.track, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await friendsManager.accept(sharerID: row.sharerID) }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(themeColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .surfaceCard()
            }
        }
    }

    // MARK: - Lo que te comparten

    private var incomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Lo que te comparten")

            VStack(spacing: 0) {
                ForEach(Array(friendsManager.acceptedIncoming.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().background(palette.separator).padding(.leading, 62)
                    }
                    incomingRow(row)
                }
            }
            .surfaceCard()
        }
    }

    private func incomingRow(_ row: FriendShareRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                friendAvatar(id: row.sharerID, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friendsManager.displayName(for: row.sharerID))
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.label)
                    Text(incomingSubtitle(row))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let total = row.totalAmount {
                    Text(Money.format(total))
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.label)
                }
            }

            if !row.categoryTotals.isEmpty {
                VStack(spacing: 7) {
                    ForEach(row.categoryTotals, id: \.name) { entry in
                        HStack(spacing: 9) {
                            Image(systemName: CategoryStyle.icon(for: entry.name))
                                .font(.caption2)
                                .foregroundStyle(CategoryStyle.color(for: entry.name, accent: themeColor))
                                .frame(width: 18)
                            Text(entry.name)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                            Spacer()
                            Text(Money.format(entry.amount))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.label)
                        }
                    }
                }
                .padding(.leading, 52)
            }
        }
        .padding(12)
    }

    /// El nombre real acompaña al apodo: si yo la guardé como "Cami", conviene
    /// que siga estando claro de quién es ese total.
    private func incomingSubtitle(_ row: FriendShareRow) -> String {
        let realName = friendsManager.name(for: row.sharerID)
        let hasNickname = friendsManager.displayName(for: row.sharerID) != realName
        let count = row.categoryTotals.count
        let detail: String
        if count == 0 {
            detail = "Solo el total del mes"
        } else {
            detail = count == 1 ? "1 categoría" : "\(count) categorías"
        }
        return hasNickname ? realName + " · " + detail : detail
    }

    // MARK: - Lo que tú compartes

    private var outgoingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Lo que tú compartes")
                Spacer()
                if !friendsManager.friends.isEmpty {
                    Text("\(sharingCount) de \(friendsManager.friends.count) amigos")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }
            }

            if friendsManager.friends.isEmpty {
                Text("Agrega a un amigo para empezar a compartir tu gasto con quien tú elijas.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .surfaceCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(friendsManager.friends.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 {
                            Divider().background(palette.separator).padding(.leading, 62)
                        }
                        Button {
                            selectedFriend = friend
                        } label: {
                            HStack(spacing: 12) {
                                friendAvatar(id: friend.id, size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(palette.label)
                                    Text(shareSummary(for: friend))
                                        .font(.caption)
                                        .foregroundStyle(isSharing(with: friend) ? palette.secondaryLabel : palette.tertiaryLabel)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(palette.tertiaryLabel)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Editar apodo y color sin tener que entrar al detalle:
                        // es una nota rápida, no una decisión de privacidad.
                        .contextMenu {
                            Button("Editar amigo") { friendToEdit = friend }
                        }
                    }
                }
                .surfaceCard()
            }
        }
    }

    /// Lo mismo que promete el diseño: "Total del mes + 2 categorías".
    private func shareSummary(for friend: Friend) -> String {
        guard let share = friendsManager.myShare(toward: friend.id) else {
            return "Sin compartir todavía"
        }
        let categories = share.shareCategories.count
        let categoryLabel = categories == 1 ? "1 categoría" : "\(categories) categorías"
        switch (share.shareTotal, categories) {
        case (true, 0):  return "Solo el total del mes"
        case (true, _):  return "Total del mes + " + categoryLabel
        case (false, 0): return "Sin compartir todavía"
        case (false, _): return categoryLabel
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.secondaryLabel)
    }

    // MARK: - Avatares

    private func friendAvatar(id: String, size: CGFloat) -> some View {
        let realName = friendsManager.name(for: id)
        let preferences = social.preferences(for: id)
        return avatar(glyph: social.glyph(for: id, realName: realName),
                      tint: social.color(for: id),
                      size: size,
                      isEmoji: preferences.emoji?.isEmpty == false)
    }

    private func avatar(glyph: String, tint: Color, size: CGFloat, isEmoji: Bool) -> some View {
        Text(glyph)
            .font(isEmoji ? .system(size: size * 0.45) : .system(size: size * 0.4, weight: .bold))
            .foregroundStyle(isEmoji ? Color.primary : .white)
            .frame(width: size, height: size)
            .background(isEmoji ? tint.opacity(0.22) : tint, in: Circle())
    }

    // MARK: - Invitar / unirme

    private var inviteCard: some View {
        Button {
            showInviteSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.title3)
                    .foregroundStyle(themeColor)
                    .frame(width: 40, height: 40)
                    .background(themeColor.opacity(colorScheme == .dark ? 0.20 : 0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Agregar un amigo")
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.label)
                    Text("Comparte tu código o canjea el suyo")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .surfaceCard()
    }

    // MARK: - Hoja de invitación

    private var inviteSheet: some View {
        NavigationStack {
            Form {
                Section {
                    if let code = myInviteCode {
                        HStack {
                            Text(code)
                                .font(.title2.monospaced().bold())
                            Spacer()
                            ShareLink(item: "Agrégame en AgruPay con el código \(code)") {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    } else {
                        Button {
                            Task {
                                isGeneratingCode = true
                                myInviteCode = await friendsManager.generateInviteCode()
                                isGeneratingCode = false
                            }
                        } label: {
                            if isGeneratingCode {
                                ProgressView()
                            } else {
                                Text("Generar mi código")
                            }
                        }
                        .disabled(isGeneratingCode)
                    }
                } header: {
                    Text("Tu código")
                } footer: {
                    Text("Válido 7 días y de un solo uso.")
                }

                Section {
                    TextField("Código de tu amigo", text: $redeemCodeDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button {
                        Task {
                            isRedeeming = true
                            let code = redeemCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                            let ok = await friendsManager.redeem(code: code)
                            isRedeeming = false
                            if ok {
                                redeemFeedback = "¡Listo! Ya son amigos."
                                redeemCodeDraft = ""
                            } else {
                                redeemFeedback = friendsManager.lastErrorMessage ?? "No se pudo canjear el código."
                            }
                        }
                    } label: {
                        if isRedeeming {
                            ProgressView()
                        } else {
                            Text("Unirme")
                        }
                    }
                    .disabled(isRedeeming || redeemCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let feedback = redeemFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                } header: {
                    Text("Unirme con un código")
                }
            }
            .navigationTitle("Agregar amigo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { showInviteSheet = false }
                }
            }
        }
    }
}

/// 1c — Tu nombre y tu estado.
///
/// Es lo único tuyo que sale del teléfono hacia tus amigos, así que la nota de
/// privacidad va aquí y no en un ajuste aparte: se lee justo cuando se decide.
struct MyProfileSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    @State private var social = SocialProfileStore.shared
    @State private var auth = SupabaseAuthManager.shared

    @State private var nameDraft = ""
    @State private var statusDraft = ""
    @State private var emojiDraft: String?
    @State private var didLoad = false

    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    /// Los mismos del diseño. No es un teclado de emoji entero a propósito: se
    /// elige de un vistazo o se deja la inicial.
    private static let emojis = ["🌵", "⚡️", "🏔️", "☕️"]
    private static let statusSuggestions = ["Ahorrando para el viaje a Cusco",
                                            "Mes tranquilo",
                                            "Sin gastos hormiga"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    avatarPicker

                    field(title: "Tu nombre") {
                        TextField("Tu nombre", text: $nameDraft)
                            .font(.body)
                            .textInputAutocapitalization(.words)
                    }

                    field(title: "Estado") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Ahorrando para el viaje a Cusco", text: $statusDraft, axis: .vertical)
                                .font(.body)
                                .lineLimit(1...2)
                                .onChange(of: statusDraft) { _, value in
                                    if value.count > SocialProfileStore.statusLimit {
                                        statusDraft = String(value.prefix(SocialProfileStore.statusLimit))
                                    }
                                }

                            HStack {
                                Spacer()
                                Text("\(statusDraft.count)/\(SocialProfileStore.statusLimit)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(palette.tertiaryLabel)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.statusSuggestions, id: \.self) { suggestion in
                                    Button { statusDraft = suggestion } label: {
                                        Text(suggestion)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(palette.label)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(palette.track, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 1)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(palette.tertiaryLabel)
                        Text("Tus amigos ven tu nombre y tu estado. Nunca tus movimientos ni tus comercios.")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
                .padding(16)
            }
            .background(palette.background)
            .navigationTitle("Tu perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Text(emojiDraft ?? SocialProfileStore.initial(of: nameDraft))
                    .font(emojiDraft == nil ? .system(size: 34, weight: .bold) : .system(size: 38))
                    .foregroundStyle(emojiDraft == nil ? Color.white : Color.primary)
                    .frame(width: 84, height: 84)
                    .background(emojiDraft == nil ? themeColor : themeColor.opacity(0.22), in: Circle())
                Spacer()
            }

            HStack(spacing: 10) {
                Spacer()
                choiceChip(label: SocialProfileStore.initial(of: nameDraft), isSelected: emojiDraft == nil) {
                    emojiDraft = nil
                }
                ForEach(Self.emojis, id: \.self) { emoji in
                    choiceChip(label: emoji, isSelected: emojiDraft == emoji) { emojiDraft = emoji }
                }
                Spacer()
            }
        }
    }

    private func choiceChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(palette.surface, in: Circle())
                .overlay(
                    Circle().stroke(isSelected ? themeColor : palette.hairline,
                                    lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)
            content()
                .padding(12)
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
        emojiDraft = social.avatarEmoji
    }

    private func save() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = statusDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await auth.updateProfile(name: name.isEmpty ? "Amigo" : name,
                                     status: status,
                                     avatarEmoji: emojiDraft)
        }
        dismiss()
    }
}

/// 1d — Editar amigo: apodo, color y avatar.
///
/// Nada de esto sale del teléfono: es cómo yo lo veo. Por eso la nota bajo el
/// apodo aclara que para él sigo siendo quien soy — un apodo no le renombra a
/// nadie del otro lado.
struct FriendEditSheet: View {

    let friend: Friend

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

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

/// 1e — Qué le muestro a un amigo.
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
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var shareTotal = false
    @State private var selectedCategories: Set<String> = []
    @State private var didLoadInitialState = false
    @State private var showStopConfirm = false
    @State private var showEditSheet = false

    private var categoryTotals: [PeriodTotals.CategoryTotal] {
        totals.byCategory.filter { Money.cents($0.total) > 0 }
            .sorted { Money.cents($0.total) > Money.cents($1.total) }
    }

    private var shownName: String { social.name(for: friend.id, realName: friend.displayName) }

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
}
