import SwiftUI
import SwiftData

/// Amigos: el hub del diseño `Amigos · Perfil y lista.dc.html` (2b/2g/2h/2f).
///
/// A diferencia de `SocialView`/`SyncManager` (el PoC de "Ver actividad de la
/// comunidad" que sigue en Ajustes → Respaldo), aquí nunca sale un movimiento
/// ni un comercio del teléfono: sólo los totales que el propio usuario marcó,
/// por amigo, con permiso explícito y revocable en cualquier momento.
///
/// Lo que suma este rediseño sobre la versión anterior:
/// - una cabecera de perfil con banner de color, nombre y **estado** editables;
/// - **apodo, color y emoji** por amigo, privados de este teléfono
///   (`SocialProfileStore`), que viajan en el respaldo de configuración;
/// - una sola lista de amigos, ordenada te comparten → sólo tú compartes →
///   nadie comparte, con las categorías de quien te comparte desplegables ahí
///   mismo en vez de exigir abrir su perfil;
/// - un perfil de amigo de lectura (`FriendProfileView`) con la historia de la
///   amistad, antes de entrar a decidir qué compartirle.
struct AmigosHubView: View {
    /// Sólo el mes en curso, que es lo único que esta pantalla enseña.
    ///
    /// Antes cargaba el historial entero para calcular un total del mes. Con
    /// varios años de correo leído eso son decenas de miles de objetos
    /// materializados —y su relación `payments` resuelta— cada vez que se
    /// dibuja la pestaña.
    @Query private var expenses: [Expense]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var scrollToTopTrigger: Bool

    init(scrollToTopTrigger: Binding<Bool>) {
        self._scrollToTopTrigger = scrollToTopTrigger

        let window = Period(granularity: .mes, reference: Date()).dataWindow()
        let start = window.start
        let end = window.end
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
                          sort: \Expense.date, order: .reverse)
    }

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
    /// El amigo que se acaba de agregar: su fila en "Sin compartir" lo resalta
    /// unos segundos con "Nuevo · elige qué le compartes" en vez del subtítulo
    /// normal. Se limpia solo — ver `flagRecentlyAdded`.
    @State private var recentlyAddedFriendID: String?

    @State private var selectedFriend: Friend?
    @State private var friendToEdit: Friend?

    /// Qué fila de "Te comparten" tiene sus categorías desplegadas (2g). Sólo
    /// una a la vez: abrir otra cierra la anterior.
    @State private var expandedFriendID: String?

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
        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 22) {
                profileBanner

                if !auth.isReady {
                    loadingCard
                } else if friendsManager.friends.isEmpty && friendsManager.acceptedIncoming.isEmpty {
                    emptyState
                } else {
                    if !friendsManager.pendingIncoming.isEmpty {
                        pendingIncomingSection
                    }
                    if !friendEntries.isEmpty {
                        friendsListSection
                    }
                    inviteCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
        .sheet(isPresented: $showInviteSheet) {
            AddFriendSheet(onJoined: flagRecentlyAdded)
        }
        .sheet(item: $selectedFriend) { friend in
            FriendProfileView(friend: friend, totals: totals,
                              incoming: friendsManager.acceptedIncoming.first { $0.sharerID == friend.id })
        }
        .sheet(item: $friendToEdit) { friend in
            FriendEditSheet(friend: friend)
        }
    }

    // MARK: - Encabezado y perfil

    /// 2b: quién soy para mis amigos, con banner de color. El estado va aquí y
    /// no en Ajustes porque es lo único que ellos ven además del nombre.
    private var profileBanner: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                SocialGradients.gradient(social.bannerIndex)
                    .frame(height: 78)

                Button {
                    showProfileSheet = true
                } label: {
                    Text("Editar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.24), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    // El aro es un círculo opaco detrás, no un trazo encima: un
                    // emoji usa `tint.opacity(0.22)` como fondo, y esa
                    // transparencia dejaba ver la costura entre el degradado y
                    // el blanco justo donde el avatar cruza el borde del
                    // banner — la mitad de arriba salía de un color y la de
                    // abajo de otro.
                    ZStack {
                        Circle()
                            .fill(palette.surface)
                            .frame(width: 64 + 7, height: 64 + 7)
                        avatar(glyph: social.avatarEmoji ?? SocialProfileStore.initial(of: social.displayName),
                               tint: themeColor, size: 64, isEmoji: social.avatarEmoji != nil)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(social.displayName.isEmpty ? "Tu nombre" : social.displayName)
                            .font(.title3.bold())
                            .foregroundStyle(palette.label)
                        Text(social.status.isEmpty ? "Añade tu estado" : social.status)
                            .font(.subheadline)
                            .foregroundStyle(social.status.isEmpty ? palette.tertiaryLabel : palette.secondaryLabel)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .offset(y: -26)
                .padding(.bottom, -26)

                bannerChips
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var bannerChips: some View {
        if !friendsManager.friends.isEmpty || !friendsManager.acceptedIncoming.isEmpty {
            HStack(spacing: 8) {
                if !friendsManager.friends.isEmpty {
                    Text("Compartes con \(sharingCount) de \(friendsManager.friends.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colorScheme == .dark ? themeColor : .white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(colorScheme == .dark ? themeColor.opacity(0.12) : themeColor, in: Capsule())
                }
                if !friendsManager.acceptedIncoming.isEmpty {
                    Text("\(friendsManager.acceptedIncoming.count) te comparten")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryLabel)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(palette.track, in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
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

    /// Sin amigos, lo que hace falta no es una lista vacía sino saber qué se
    /// gana y cómo empezar.
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .surfaceCard()
            }
        }
    }

    // MARK: - Lista única de amigos (2g)

    private enum ShareBucket { case sharesWithMe, onlyIShare, none }

    private struct FriendListEntry: Identifiable {
        let friend: Friend
        let bucket: ShareBucket
        let incoming: FriendShareRow?
        var id: String { friend.id }
    }

    /// Orden fijo: te comparten → sólo tú compartes → nadie comparte.
    private var friendEntries: [FriendListEntry] {
        friendsManager.friends.map { friend in
            if let incoming = friendsManager.acceptedIncoming.first(where: { $0.sharerID == friend.id }) {
                return FriendListEntry(friend: friend, bucket: .sharesWithMe, incoming: incoming)
            } else if isSharing(with: friend) {
                return FriendListEntry(friend: friend, bucket: .onlyIShare, incoming: nil)
            } else {
                return FriendListEntry(friend: friend, bucket: .none, incoming: nil)
            }
        }
    }

    private var sharesWithMeEntries: [FriendListEntry] { friendEntries.filter { $0.bucket == .sharesWithMe } }
    private var onlyIShareEntries: [FriendListEntry] { friendEntries.filter { $0.bucket == .onlyIShare } }
    private var noShareEntries: [FriendListEntry] { friendEntries.filter { $0.bucket == .none } }

    private var friendsListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Amigos")

            VStack(spacing: 0) {
                if !sharesWithMeEntries.isEmpty {
                    groupHeader("Te comparten", count: sharesWithMeEntries.count)
                    groupedRows(sharesWithMeEntries, dividerLeading: 64, row: sharesWithMeRow)
                }
                if !onlyIShareEntries.isEmpty {
                    groupHeader("Solo tú compartes", count: onlyIShareEntries.count)
                    groupedRows(onlyIShareEntries, dividerLeading: 64, row: onlyIShareRow)
                }
                if !noShareEntries.isEmpty {
                    groupHeader("Sin compartir", count: noShareEntries.count)
                    groupedRows(noShareEntries, dividerLeading: 58, row: noShareRow)
                }
            }
            .surfaceCard(padding: 0)
        }
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(palette.secondaryLabel)
            Text("· \(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    @ViewBuilder
    private func groupedRows<RowContent: View>(_ entries: [FriendListEntry], dividerLeading: CGFloat,
                                               @ViewBuilder row: @escaping (FriendListEntry) -> RowContent) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            if index > 0 {
                Divider().background(palette.separator).padding(.leading, dividerLeading)
            }
            row(entry)
        }
    }

    /// Fila de quien te comparte: nombre, hace cuántos días son amigos, y su
    /// desglose si marcó categorías — desplegable ahí mismo (2g). Tocar el
    /// nombre lleva a su perfil; tocar el `⌄` sólo despliega.
    private func sharesWithMeRow(_ entry: FriendListEntry) -> some View {
        guard let incoming = entry.incoming else { return AnyView(EmptyView()) }
        let hasCategories = !incoming.categoryTotals.isEmpty
        let isExpanded = expandedFriendID == entry.friend.id

        return AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    colorBar(tint: entry.friend.tint, height: 56)
                    friendAvatar(id: entry.friend.id, size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(friendsManager.displayName(for: entry.friend.id))
                                .font(.subheadline.bold())
                                .foregroundStyle(palette.label)
                            if let badge = friendshipDaysBadge(entry.friend) {
                                Text(badge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(entry.friend.tint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(entry.friend.tint.opacity(0.16), in: Capsule())
                            }
                        }
                        Text(rowSubtitle(for: entry.friend, bucket: .sharesWithMe, incoming: incoming))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        if let total = incoming.totalAmount {
                            Text(Money.format(total))
                                .font(.subheadline.bold())
                                .foregroundStyle(palette.label)
                        }
                        if hasCategories {
                            Text(incoming.categoryTotals.count == 1 ? "1 categoría" : "\(incoming.categoryTotals.count) categorías")
                                .font(.caption2)
                                .foregroundStyle(palette.tertiaryLabel)
                        }
                    }

                    Button {
                        if hasCategories {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedFriendID = isExpanded ? nil : entry.friend.id
                            }
                        } else {
                            selectedFriend = entry.friend
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(palette.tertiaryLabel)
                            .rotationEffect(.degrees(hasCategories && isExpanded ? 180 : -90))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { selectedFriend = entry.friend }

                if hasCategories && isExpanded {
                    categoryBreakdown(incoming)
                        .padding(.leading, 64)
                        .padding(.trailing, 14)
                        .padding(.bottom, 12)
                }
            }
        )
    }

    private func categoryBreakdown(_ incoming: FriendShareRow) -> some View {
        let largest = incoming.categoryTotals.map(\.amount).max() ?? 1
        let shownTotal = Money.sum(incoming.categoryTotals) { $0.amount }
        let hasRest = (incoming.totalAmount ?? 0) > 0 && Money.cents(incoming.totalAmount ?? 0) > Money.cents(shownTotal)

        return VStack(alignment: .leading, spacing: 9) {
            ForEach(incoming.categoryTotals, id: \.name) { entry in
                HStack(spacing: 9) {
                    Image(systemName: CategoryStyle.icon(for: entry.name))
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryLabel)
                        .frame(width: 18)
                    Text(entry.name)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    GeometryReader { geo in
                        Capsule().fill(palette.track)
                            .overlay(alignment: .leading) {
                                Capsule().fill(themeColor)
                                    .frame(width: geo.size.width * CGFloat(min(1, Money.ratio(entry.amount, to: largest) ?? 0)))
                            }
                    }
                    .frame(height: 5)
                    Text(Money.format(entry.amount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.label)
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
            if hasRest {
                Text("El resto de su total no está desglosado.")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
            }
        }
    }

    /// Fila de a quien sólo tú compartes.
    private func onlyIShareRow(_ entry: FriendListEntry) -> some View {
        Button {
            selectedFriend = entry.friend
        } label: {
            HStack(spacing: 12) {
                colorBar(tint: entry.friend.tint, height: 56)
                friendAvatar(id: entry.friend.id, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friendsManager.displayName(for: entry.friend.id))
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.label)
                    Text(rowSubtitle(for: entry.friend, bucket: .onlyIShare, incoming: nil))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Editar amigo") { friendToEdit = entry.friend }
        }
    }

    /// Fila de con quien no se comparte nada todavía: un botón directo en vez
    /// de sólo desvanecerse.
    private func noShareRow(_ entry: FriendListEntry) -> some View {
        let isNew = entry.friend.id == recentlyAddedFriendID
        return HStack(spacing: 12) {
            colorBar(tint: entry.friend.tint.opacity(0.55), height: 44)
            friendAvatar(id: entry.friend.id, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(friendsManager.displayName(for: entry.friend.id))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
                Text(isNew ? "Nuevo · elige qué le compartes" : rowSubtitle(for: entry.friend, bucket: .none, incoming: nil))
                    .font(.caption2.weight(isNew ? .semibold : .regular))
                    .foregroundStyle(isNew ? themeColor : palette.tertiaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                if isNew { recentlyAddedFriendID = nil }
                selectedFriend = entry.friend
            } label: {
                Text("Compartir")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? themeColor : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(colorScheme == .dark ? themeColor.opacity(0.12) : themeColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isNew ? themeColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 1.2), value: recentlyAddedFriendID)
        .onTapGesture {
            if isNew { recentlyAddedFriendID = nil }
            selectedFriend = entry.friend
        }
        .contextMenu {
            Button("Editar amigo") { friendToEdit = entry.friend }
        }
    }

    /// El "lomo" de color: da el tinte del amigo sin ocupar ancho de la fila.
    private func colorBar(tint: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            .frame(width: 4, height: height)
    }

    /// Prioridad: su estado, si lo escribió; si no, el detalle propio de cada
    /// grupo — lo que comparte, hace cuánto le compartes, o desde cuándo son
    /// amigos.
    private func rowSubtitle(for friend: Friend, bucket: ShareBucket, incoming: FriendShareRow?) -> String {
        if !friend.status.isEmpty { return friend.status }
        switch bucket {
        case .sharesWithMe:
            guard let incoming else { return "Te comparte su gasto" }
            return incomingSubtitle(incoming)
        case .onlyIShare:
            if let days = daysSharingWith(friend) {
                return "Le compartes hace " + dayCount(days)
            }
            return shareSummary(for: friend)
        case .none:
            if let since = friend.friendSince {
                return "Amigos desde " + Period.spanishMonthName(for: since).lowercased()
            }
            return "Sin compartir todavía"
        }
    }

    /// El nombre real acompaña al detalle: si yo lo guardé como "Cami",
    /// conviene que siga estando claro de quién es ese total.
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

    private func dayCount(_ days: Int) -> String { "\(days) día" + (days == 1 ? "" : "s") }

    /// Hace cuántos días toqué por última vez lo que le comparto — lo más
    /// cercano a "desde cuándo" que este teléfono conoce de verdad.
    private func daysSharingWith(_ friend: Friend) -> Int? {
        guard let updatedAt = social.preferences(for: friend.id).sharedUpdatedAt else { return nil }
        return max(0, Period.calendar.dateComponents([.day], from: updatedAt, to: Date()).day ?? 0)
    }

    /// "N d" junto al nombre de quien te comparte: días desde que son amigos.
    private func friendshipDaysBadge(_ friend: Friend) -> String? {
        guard let since = friend.friendSince else { return nil }
        let days = max(0, Period.calendar.dateComponents([.day], from: since, to: Date()).day ?? 0)
        return "\(days) d"
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
                    .foregroundStyle(colorScheme == .dark ? themeColor : .white)
                    .frame(width: 40, height: 40)
                    .background(colorScheme == .dark ? themeColor.opacity(0.20) : themeColor, in: Circle())

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

    // MARK: - Recién agregado

    /// El resaltado de la fila lo hace la propia `.animation` de `noShareRow`
    /// reaccionando a `recentlyAddedFriendID`: aquí sólo se agenda cuándo se
    /// apaga, para que no se quede resaltado para siempre si el usuario no
    /// toca la fila.
    private func flagRecentlyAdded(_ id: String) {
        recentlyAddedFriendID = id
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if recentlyAddedFriendID == id {
                recentlyAddedFriendID = nil
            }
        }
    }
}

/// 2c — el flujo completo de "Agregar amigo": código propio listo al abrir,
/// canjear el de un amigo con éxito animado, y la hoja se retira sola.
///
/// `onJoined` avisa a `AmigosHubView` quién se acaba de agregar para que la
/// fila en "Sin compartir" lo resalte — esta hoja no toca esa lista
/// directamente, sólo reporta el id.
struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onJoined: (String) -> Void

    @State private var friendsManager = FriendsManager.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var myCode: String?
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
            } else {
                formContent
            }
        }
        .task { await ensureCode() }
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
                    ShareLink(item: "Agrégame en AgruPay con el código \(myCode)") {
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

/// 2h — Tu nombre, tu estado y la cabecera de tu perfil.
///
/// Vista previa arriba y controles abajo: se edita viendo el resultado. Es lo
/// único tuyo que sale del teléfono hacia tus amigos, así que la nota de
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
    @State private var bannerDraft = 0
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
                    headerPreview
                    bannerPicker
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
                        Text("Tus amigos ven tu nombre, tu ícono, tu cabecera y tu estado. Nunca tus movimientos ni tus comercios.")
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

    /// Vista previa de la cabecera tal como la verán tus amigos.
    private var headerPreview: some View {
        ZStack(alignment: .bottomLeading) {
            SocialGradients.gradient(bannerDraft)
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 60 + 6, height: 60 + 6)
                Text(emojiDraft ?? SocialProfileStore.initial(of: nameDraft))
                    .font(emojiDraft == nil ? .system(size: 26, weight: .bold) : .system(size: 30))
                    .foregroundStyle(emojiDraft == nil ? Color.white : Color.primary)
                    .frame(width: 60, height: 60)
                    .background(emojiDraft == nil ? themeColor : themeColor.opacity(0.22), in: Circle())
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .padding(14)
        }
    }

    private var bannerPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CABECERA")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)

            HStack(spacing: 8) {
                ForEach(SocialGradients.all.indices, id: \.self) { index in
                    Button { bannerDraft = index } label: {
                        SocialGradients.gradient(index)
                            .frame(height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(bannerDraft == index ? themeColor : Color.clear, lineWidth: 2)
                                    .padding(-2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("ÍCONO")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)

            HStack(spacing: 10) {
                choiceChip(label: SocialProfileStore.initial(of: nameDraft), isSelected: emojiDraft == nil) {
                    emojiDraft = nil
                }
                ForEach(Self.emojis, id: \.self) { emoji in
                    choiceChip(label: emoji, isSelected: emojiDraft == emoji) { emojiDraft = emoji }
                }
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
        bannerDraft = social.bannerIndex ?? 0
    }

    private func save() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = statusDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        social.bannerIndex = bannerDraft
        Task {
            await auth.updateProfile(name: name.isEmpty ? "Amigo" : name,
                                     status: status,
                                     avatarEmoji: emojiDraft)
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
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var showEditSheet = false
    @State private var showShareEditor = false
    @State private var showStopConfirm = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var shownName: String { social.name(for: friend.id, realName: friend.displayName) }
    private var hasNickname: Bool { friend.hasNickname }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    VStack(spacing: 14) {
                        if !friend.status.isEmpty { statusCard }
                        statsRow
                        if let incoming { theyShareCard(incoming) }
                        weShareCard
                        privacyNote
                        destructiveActions
                    }
                    .padding(16)
                }
            }
            .background(palette.background)
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

    /// Como en 2f: el degradado no encierra el avatar, lo deja cruzar hacia el
    /// contenido de abajo (`offset` + `padding.bottom` negativos, igual que
    /// `profileBanner`). El respaldo circular opaco detrás del avatar —no un
    /// trazo encima— es lo que evita que su propio fondo (`tint.opacity(0.22)`
    /// para un emoji) deje ver la costura entre el degradado y el fondo de la
    /// pantalla justo donde el avatar cruza ese borde.
    private var header: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [friend.tint, friend.tint.opacity(0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 96)

            HStack(alignment: .bottom, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(palette.background)
                        .frame(width: 76 + 8, height: 76 + 8)
                    avatar
                }
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(shownName)
                        .font(.title2.bold())
                        .foregroundStyle(palette.label)
                    if hasNickname {
                        Text(friend.displayName + " · apodo solo tuyo")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
                .padding(.bottom, 8)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .offset(y: -34)
            .padding(.bottom, -34)
        }
        .background(palette.background)
    }

    private var avatar: some View {
        let preferences = social.preferences(for: friend.id)
        let usesEmoji = preferences.emoji?.isEmpty == false
        return Text(social.glyph(for: friend.id, realName: friend.displayName))
            .font(usesEmoji ? .system(size: 34) : .system(size: 30, weight: .bold))
            .foregroundStyle(usesEmoji ? Color.primary : Color.white)
            .frame(width: 76, height: 76)
            .background(usesEmoji ? friend.tint.opacity(0.22) : friend.tint, in: Circle())
    }

    // MARK: - Estado, estadísticas

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SU ESTADO")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(friend.tint)
            Text(friend.status)
                .font(.body)
                .foregroundStyle(palette.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(friend.tint.opacity(colorScheme == .dark ? 0.16 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Dos cifras y a propósito, las dos del mismo dato: la fecha en que se
    /// hicieron amigos, y hace cuántos días es eso — el único momento que
    /// este teléfono conoce con certeza (cuándo empezaron a *compartirse*
    /// algo no se guarda por separado).
    private var statsRow: some View {
        HStack(spacing: 8) {
            statCard(value: friendSinceText, label: "amigos desde")
            statCard(value: friendSinceDaysText, label: "días de amistad", tint: friend.tint)
        }
    }

    private func statCard(value: String, label: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint ?? palette.label)
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surfaceCard(padding: 0)
        .padding(1)
    }

    private var friendSinceText: String {
        guard let date = friend.friendSince else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private var friendSinceDaysText: String {
        guard let date = friend.friendSince else { return "—" }
        let days = max(0, Period.calendar.dateComponents([.day], from: date, to: Date()).day ?? 0)
        return "\(days) días"
    }

    // MARK: - Lo que te comparte / lo que tú le compartes

    private func theyShareCard(_ incoming: FriendShareRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lo que te comparte")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Spacer()
                if let total = incoming.totalAmount {
                    Text(Money.format(total))
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.label)
                }
            }
            .padding(13)

            if !incoming.categoryTotals.isEmpty {
                ForEach(incoming.categoryTotals, id: \.name) { entry in
                    Divider().background(palette.separator).padding(.leading, 14)
                    HStack {
                        Text(entry.name)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryLabel)
                        Spacer()
                        Text(Money.format(entry.amount))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.label)
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                }
            }
        }
        .surfaceCard(padding: 0)
    }

    private var weShareCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lo que tú le compartes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.label)
                Text(shareSummary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Button("Cambiar") { showShareEditor = true }
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(themeColor.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(13)
        .surfaceCard(padding: 0)
    }

    private var shareSummary: String {
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

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(palette.tertiaryLabel)
            Text("Ve lo que marques y nada más. Nunca tus comercios ni tus movimientos.")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Acciones destructivas

    @ViewBuilder
    private var destructiveActions: some View {
        VStack(spacing: 10) {
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
