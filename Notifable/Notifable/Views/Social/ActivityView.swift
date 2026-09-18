import SwiftUI
import SwiftData

/// Social › Actividad (`2g`), la sub-vista por defecto de la pestaña.
///
/// Solicitudes arriba y feed debajo. Antes esto era el primer tercio de un
/// scroll único de 2,400 líneas que además llevaba la lista de amigos, el
/// canje de códigos y el editor del pingüino; lo que te comparten se perdía
/// entre la configuración de lo que tú compartes.
struct ActivityView: View {
    @Binding var scrollToTopTrigger: Bool
    let progress: ScrollProgress

    @Environment(\.colorScheme) private var scheme
    @Query private var expenses: [Expense]
    @StateObject private var rates = ExchangeRateService.shared
    @State private var friendsManager = FriendsManager.shared
    @State private var auth = SupabaseAuthManager.shared

    @State private var showProfileSheet = false
    @State private var selectedFriend: Friend?
    @State private var expandedFriendID: String?

    init(scrollToTopTrigger: Binding<Bool>, progress: ScrollProgress) {
        self._scrollToTopTrigger = scrollToTopTrigger
        self.progress = progress

        // Sólo el mes en curso: es lo único que esta pantalla enseña, y
        // cargar el historial entero para un total del mes materializa
        // decenas de miles de objetos.
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
        let pending = friendsManager.pendingIncoming
        let feed = friendsManager.acceptedIncoming

        TrackableScrollView(scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 12) {
                ShellTitle(title: "Actividad",
                           subtitle: feed.isEmpty ? nil
                               : "\(feed.count) te comparten su gasto del mes")

                if !auth.isReady {
                    ShellCard {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Conectando…")
                                .font(.system(size: 14))
                                .foregroundStyle(palette.secondaryLabel)
                        }
                    }
                } else if pending.isEmpty && feed.isEmpty {
                    ShellEmptyState(icon: "bolt",
                                    title: "Todavía nadie te comparte",
                                    message: "Agrega amigos con su código y pídeles que te compartan su gasto del mes.")
                } else {
                    ForEach(pending, id: \.id) { row in
                        requestCard(row)
                    }

                    ForEach(feed, id: \.id) { row in
                        feedCard(row)
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
        .sheet(isPresented: $showProfileSheet) { MyProfileSheet() }
        .sheet(item: $selectedFriend) { friend in
            FriendProfileView(friend: friend, totals: totals,
                              incoming: friendsManager.acceptedIncoming.first { $0.sharerID == friend.id })
        }
    }

    // MARK: - Solicitudes

    private func requestCard(_ row: FriendShareRow) -> some View {
        let friend = friendsManager.friend(with: row.sharerID)

        return ShellCard {
            HStack(spacing: 12) {
                FriendAvatar(friend: friend)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.label)
                    Text("Quiere compartirte su gasto del mes")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer(minLength: 6)

                HStack(spacing: 6) {
                    Button {
                        Task { await friendsManager.accept(sharerID: row.sharerID) }
                    } label: {
                        Text("Aceptar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(accent.color, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await friendsManager.ignore(sharerID: row.sharerID) }
                    } label: {
                        Text("Rechazar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.secondaryLabel)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(palette.neutralSurface, in: Capsule())
                            .overlay(Capsule().stroke(palette.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Feed

    private func feedCard(_ row: FriendShareRow) -> some View {
        let friend = friendsManager.friend(with: row.sharerID)
        let isExpanded = expandedFriendID == friend.id
        let categories = row.categoryTotals

        return Button {
            selectedFriend = friend
        } label: {
            ShellCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        FriendAvatar(friend: friend)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.label)

                            Text(friend.status.isEmpty
                                 ? "Su gasto de " + Period.spanishMonthName(for: Date()).lowercased()
                                 : "«" + friend.status + "»")
                                .font(.system(size: 12.5))
                                .foregroundStyle(palette.secondaryLabel)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        if let total = row.totalAmount, row.shareTotal {
                            Text(Money.format(total))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(palette.label)
                        }
                    }

                    if !categories.isEmpty {
                        categoryChips(categories)

                        // Sólo cuando comparte total **y** categorías tiene
                        // sentido avisar de que el desglose no cubre todo.
                        if isExpanded, row.shareTotal {
                            Text("El resto de su total no está desglosado.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.tertiaryLabel)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedFriendID = isExpanded ? nil : friend.id
            }
        }
    }

    private func categoryChips(_ categories: [FriendShareRow.CategoryAmount]) -> some View {
        HStack(spacing: 6) {
            ForEach(categories.prefix(3), id: \.name) { category in
                HStack(spacing: 4) {
                    Image(systemName: CategoryStyle.icon(for: category.name))
                        .font(.system(size: 10, weight: .semibold))
                    Text(category.name + " " + Money.formatCompact(category.amount)
                        .replacingOccurrences(of: "S/ ", with: ""))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(CategoryStyle.color(for: category.name, accent: accent.color))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(CategoryStyle.color(for: category.name, accent: accent.color).opacity(0.14),
                            in: Capsule())
            }

            Spacer(minLength: 0)
        }
    }
}
