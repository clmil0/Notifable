import SwiftUI
import SwiftData

/// Social › Amigos (`2h`).
///
/// Lista única con **el estado de compartir como subtítulo**: recíproco, sólo
/// tú, sólo él. Antes había una sección por estado, así que un amigo cambiaba
/// de sitio en la pantalla al tocarle el interruptor y costaba encontrarlo otra
/// vez. Invitar y canjear viven arriba, juntos, no repartidos por la pantalla.
struct FriendsListView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.colorScheme) private var scheme
    @Query private var expenses: [Expense]
    @StateObject private var rates = ExchangeRateService.shared
    @State private var friendsManager = FriendsManager.shared
    @State private var auth = SupabaseAuthManager.shared
    @State private var inviteRouter = FriendInviteRouter.shared

    @State private var showProfileSheet = false
    @State private var showInviteSheet = false
    @State private var invitedCode: String?
    @State private var selectedFriend: Friend?
    @State private var myCode: String?
    @State private var copied = false

    init(scrollToTopTrigger: Binding<Bool>, progress: ScrollProgress) {
        self._scrollToTopTrigger = scrollToTopTrigger
        self.progress = progress

        let window = Period(granularity: .mes, reference: Date()).dataWindow()
        let start = window.start
        let end = window.end
        _expenses = Query(filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
                          sort: \Expense.date, order: .reverse)
    }

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses, incomes: [],
                          period: Period(granularity: .mes, reference: Date()),
                          usdToPen: rates.usdToPenRate)
    }

    var body: some View {
        let friends = friendsManager.friends

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 14) {
                ShellTitle(title: "Amigos",
                           subtitle: "Se agregan con un código, no por nombre.")

                actions

                if let myCode {
                    codeCard(myCode)
                }

                if friends.isEmpty {
                    ShellEmptyState(icon: "person.2",
                                    title: "Todavía no tienes amigos aquí",
                                    message: "Comparte tu código o canjea el de alguien para empezar.")
                } else {
                    VStack(spacing: 8) {
                        ShellSectionHeader(title: friends.count == 1 ? "1 amigo"
                                                                    : "\(friends.count) amigos")
                        MovementCard {
                            ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                                friendRow(friend)
                                if index < friends.count - 1 { MovementSeparator() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, ShellMetrics.contentTopInset)
            .padding(.bottom, ShellMetrics.contentBottomInset)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            progress.update(offset)
        }
        .socialSession(showProfileSheet: $showProfileSheet)
        .task { myCode = await friendsManager.myFriendCode() }
        .onChange(of: auth.isReady) { _, ready in
            guard ready else { return }
            Task { myCode = await friendsManager.myFriendCode() }
            presentPendingInvite()
        }
        .onChange(of: inviteRouter.pendingCode) { _, _ in presentPendingInvite() }
        .sheet(isPresented: $showProfileSheet) { MyProfileSheet() }
        .sheet(isPresented: $showInviteSheet, onDismiss: { invitedCode = nil }) {
            AddFriendSheet(invitedCode: invitedCode, onJoined: { _ in })
        }
        .sheet(item: $selectedFriend) { friend in
            FriendProfileView(friend: friend, totals: totals,
                              incoming: friendsManager.acceptedIncoming.first { $0.sharerID == friend.id })
        }
    }

    // MARK: - Acciones

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                shareMyCode()
            } label: {
                actionLabel(icon: "square.and.arrow.up", title: "Compartir mi código", filled: true)
            }
            .buttonStyle(.plain)

            Button {
                showInviteSheet = true
            } label: {
                actionLabel(icon: "ticket", title: "Canjear", filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(icon: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Color.white : palette.label)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(filled ? AnyShapeStyle(accent.color) : AnyShapeStyle(palette.surface), in: Capsule())
        .overlay(Capsule().stroke(filled ? Color.clear : palette.hairline, lineWidth: 0.5))
    }

    // MARK: - Mi código

    private func codeCard(_ code: String) -> some View {
        VStack(spacing: 8) {
            ShellSectionHeader(title: "Tu código")

            ShellCard {
                HStack(spacing: 12) {
                    Text(code)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(palette.label)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = code
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(copied ? palette.positive : palette.secondaryLabel)
                            .frame(width: 36, height: 36)
                            .background(palette.neutralSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copiar mi código")

                    Button(action: shareMyCode) {
                        Image(systemName: "message")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(palette.secondaryLabel)
                            .frame(width: 36, height: 36)
                            .background(palette.neutralSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Compartir por WhatsApp")
                }
            }
        }
    }

    // MARK: - Fila

    private func friendRow(_ friend: Friend) -> some View {
        let state = shareState(with: friend)

        return Button {
            selectedFriend = friend
        } label: {
            HStack(spacing: 12) {
                FriendAvatar(friend: friend)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Image(systemName: state.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(state.label)
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(palette.secondaryLabel)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.tertiaryLabel)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Los cuatro estados posibles de una amistad, dichos desde mi lado.
    private func shareState(with friend: Friend) -> (icon: String, label: String) {
        let mine = friendsManager.myShare(toward: friend.id)
        let iShare = (mine?.shareTotal ?? false) || !(mine?.shareCategories.isEmpty ?? true)
        let theyShare = friendsManager.acceptedIncoming.contains { $0.sharerID == friend.id }
        let theyOffered = friendsManager.pendingIncoming.contains { $0.sharerID == friend.id }

        switch (iShare, theyShare) {
        case (true, true):   return ("arrow.left.arrow.right", "Recíproco")
        case (true, false):  return theyOffered
            ? ("clock", "Te quiere compartir")
            : ("arrow.right", "Sólo tú le compartes")
        case (false, true):  return ("arrow.left", "Sólo él te comparte")
        case (false, false): return ("minus", "Sin compartir")
        }
    }

    // MARK: - Invitación

    private func shareMyCode() {
        guard let code = myCode else { return }
        let link = "https://agrupay.app/i/" + code
        let text = "Agrégame en AgruPay con mi código \(code): \(link)"
        guard let url = URL(string: "https://wa.me/?text=" + (text.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? "")) else { return }
        UIApplication.shared.open(url)
    }

    /// Sin sesión no se puede canjear: el código espera en el router hasta que
    /// `auth.isReady`.
    private func presentPendingInvite() {
        guard auth.isReady, inviteRouter.pendingCode != nil, let code = inviteRouter.take() else { return }
        invitedCode = code
        showInviteSheet = true
    }
}
