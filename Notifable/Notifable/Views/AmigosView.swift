import SwiftUI
import SwiftData

/// Amigos: modelo "2a" del diseño (`social_agrupay/Social · compartir gastos.dc.html`) —
/// un hub con lo que te comparten y lo que tú compartes, y una pantalla de
/// detalle por amigo donde decides qué categorías ve.
///
/// A diferencia de `SocialView`/`SyncManager` (el PoC de "Ver actividad de la
/// comunidad" que sigue en Ajustes → Respaldo), aquí nunca sale un movimiento
/// ni un comercio del teléfono: sólo los totales que el propio usuario marcó,
/// por amigo, con permiso explícito y revocable en cualquier momento.
struct AmigosHubView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var scrollOffset: CGFloat
    @Binding var scrollToTopTrigger: Bool

    @StateObject private var exchangeRateService = ExchangeRateService.shared
    @State private var friendsManager = FriendsManager.shared
    @State private var auth = SupabaseAuthManager.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var didStartSession = false
    @State private var showNamePrompt = false
    @State private var nameDraft = ""

    @State private var showInviteSheet = false
    @State private var myInviteCode: String?
    @State private var isGeneratingCode = false
    @State private var redeemCodeDraft = ""
    @State private var isRedeeming = false
    @State private var redeemFeedback: String?

    @State private var selectedFriend: Friend?

    /// El mismo `Period` que Resumen, Categorías y Ritmo — el mes actual.
    private var period: Period { Period(granularity: .mes, reference: Date()) }

    private var totals: PeriodTotals {
        Accounting.totals(expenses: expenses,
                          incomes: [],
                          period: period,
                          usdToPen: exchangeRateService.usdToPenRate)
    }

    var body: some View {
        TrackableScrollView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger) {
            VStack(spacing: 24) {
                header

                if !auth.isReady {
                    loadingCard
                } else {
                    inviteCard

                    if !friendsManager.pendingIncoming.isEmpty {
                        pendingIncomingSection
                    }

                    if !friendsManager.acceptedIncoming.isEmpty {
                        acceptedIncomingSection
                    }

                    friendsSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
        .task {
            guard !didStartSession else { return }
            didStartSession = true
            let defaultName = "Amigo"
            let ready = await auth.ensureSession(defaultName: defaultName)
            if ready, auth.displayName == defaultName || auth.displayName == nil {
                nameDraft = defaultName
                showNamePrompt = true
            }
            await friendsManager.refresh()
        }
        .refreshable {
            await friendsManager.refresh()
        }
        .sheet(isPresented: $showNamePrompt) {
            namePromptSheet
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
        .sheet(item: $selectedFriend) { friend in
            AmigoDetailView(friend: friend, totals: totals)
        }
    }

    // MARK: - Encabezado

    private var header: some View {
        HStack {
            Text("Amigos")
                .font(.largeTitle.bold())
            Spacer()
        }
        .padding(.top, 8)
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

    // MARK: - Invitar / unirme

    private var inviteCard: some View {
        Button {
            showInviteSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.title3)
                    .foregroundStyle(themeColor)
                    .frame(width: 36, height: 36)
                    .background(themeColor.opacity(colorScheme == .dark ? 0.20 : 0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Agregar un amigo")
                        .font(.subheadline.bold())
                        .foregroundStyle(palette.label)
                    Text("Comparte un código o canjea el suyo")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(palette.tertiaryLabel)
            }
        }
        .buttonStyle(.plain)
        .padding(16)
        .surfaceCard()
    }

    private var namePromptSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tu nombre", text: $nameDraft)
                } header: {
                    Text("¿Cómo te ven tus amigos?")
                } footer: {
                    Text("Sólo tu nombre — nunca tus movimientos ni comercios.")
                }
            }
            .navigationTitle("Amigos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await auth.updateDisplayName(trimmed.isEmpty ? "Amigo" : trimmed)
                        }
                        showNamePrompt = false
                    }
                }
            }
        }
        .presentationDetents([.height(220)])
    }

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

    // MARK: - Te quieren compartir

    private var pendingIncomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Te quieren compartir")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(friendsManager.pendingIncoming) { row in
                    HStack(spacing: 12) {
                        avatarInitial(for: row.sharerID)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(friendsManager.name(for: row.sharerID))
                                .font(.subheadline.bold())
                            Text("Quiere compartirte su gasto de este mes")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                        }

                        Spacer()

                        Button {
                            Task { await friendsManager.ignore(sharerID: row.sharerID) }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await friendsManager.accept(sharerID: row.sharerID) }
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(themeColor)
                    }
                    .padding(12)
                    .background(palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(12)
            .surfaceCard()
        }
    }

    // MARK: - Lo que te comparten

    private var acceptedIncomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lo que te comparten")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(friendsManager.acceptedIncoming.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider().background(palette.separator)
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
                avatarInitial(for: row.sharerID)

                Text(friendsManager.name(for: row.sharerID))
                    .font(.subheadline.bold())

                Spacer()

                if let total = row.totalAmount {
                    Text(Money.format(total))
                        .font(.subheadline.bold())
                        .foregroundStyle(themeColor)
                }
            }

            if !row.categoryTotals.isEmpty {
                VStack(spacing: 6) {
                    ForEach(row.categoryTotals, id: \.name) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: CategoryStyle.icon(for: entry.name))
                                .font(.caption)
                                .foregroundStyle(CategoryStyle.color(for: entry.name, accent: themeColor))
                                .frame(width: 18)
                            Text(entry.name)
                                .font(.caption)
                                .foregroundStyle(palette.secondaryLabel)
                            Spacer()
                            Text(Money.format(entry.amount))
                                .font(.caption.bold())
                        }
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Lo que tú compartes

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lo que tú compartes")
                .font(.headline)

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
                            Divider().background(palette.separator)
                        }
                        Button {
                            selectedFriend = friend
                        } label: {
                            HStack(spacing: 12) {
                                avatarInitial(for: friend.id, name: friend.displayName)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.displayName)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(palette.label)
                                    Text(shareSummary(for: friend))
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryLabel)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(palette.tertiaryLabel)
                            }
                            .padding(12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .surfaceCard()
            }
        }
    }

    private func shareSummary(for friend: Friend) -> String {
        guard let share = friendsManager.myShare(toward: friend.id) else {
            return "Sin compartir todavía"
        }
        let sharingSomething = share.shareTotal || !share.shareCategories.isEmpty
        return sharingSomething ? "Compartiendo este mes" : "Sin compartir todavía"
    }

    private func avatarInitial(for id: String, name: String? = nil) -> some View {
        let displayName = name ?? friendsManager.name(for: id)
        let friend = Friend(id: id, displayName: displayName)
        return Text(friend.initial)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(friend.tint, in: Circle())
    }
}

/// Detalle de un amigo: qué le muestro este mes. Las categorías salen de mis
/// propios totales del periodo — nunca de lo que él ya ve, para que marcar o
/// desmarcar sea inmediato y no dependa de una segunda llamada de red.
struct AmigoDetailView: View {
    let friend: Friend
    let totals: PeriodTotals

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var friendsManager = FriendsManager.shared

    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    private var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    private var palette: Palette { Palette(colorScheme) }

    @State private var shareTotal = false
    @State private var selectedCategories: Set<String> = []
    @State private var didLoadInitialState = false
    @State private var isSavingChange = false
    @State private var showStopConfirm = false

    private var categoryTotals: [PeriodTotals.CategoryTotal] {
        totals.byCategory.filter { Money.cents($0.total) > 0 }
            .sorted { Money.cents($0.total) > Money.cents($1.total) }
    }

    private var previewAmount: Double {
        var amount: Double = 0
        if shareTotal { amount = totals.spent }
        else {
            amount = Money.sum(categoryTotals.filter { selectedCategories.contains($0.category) }) { $0.total }
        }
        return amount
    }

    private var isSharingAnything: Bool {
        shareTotal || !selectedCategories.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(friend.initial)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(friend.tint, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName)
                                .font(.title3.bold())
                            Text("Verá hoy: \(Money.format(isSharingAnything ? previewAmount : 0))")
                                .font(.subheadline)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Total del mes", isOn: $shareTotal)
                        .tint(themeColor)
                } footer: {
                    Text("El monto que ves en Resumen — sin el detalle por categoría.")
                }

                Section {
                    ForEach(categoryTotals) { entry in
                        Button {
                            toggleCategory(entry.category)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: CategoryStyle.icon(for: entry.category))
                                    .foregroundStyle(CategoryStyle.color(for: entry.category, accent: themeColor))
                                    .frame(width: 22)
                                Text(entry.category)
                                    .foregroundStyle(palette.label)
                                Spacer()
                                Text(Money.format(entry.total))
                                    .font(.subheadline)
                                    .foregroundStyle(palette.secondaryLabel)
                                Image(systemName: selectedCategories.contains(entry.category) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedCategories.contains(entry.category) ? themeColor : palette.tertiaryLabel)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Categorías elegidas")
                } footer: {
                    Text("Sólo las que marques salen de tu teléfono — nunca los comercios ni los movimientos.")
                }

                if friendsManager.myShare(toward: friend.id) != nil {
                    Section {
                        Button(role: .destructive) {
                            showStopConfirm = true
                        } label: {
                            Text("Dejar de compartir con \(friend.displayName)")
                        }
                    }
                }
            }
            .navigationTitle("Compartir con \(friend.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .confirmationDialog("¿Dejar de compartir con \(friend.displayName)?",
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

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true
        guard let existing = friendsManager.myShare(toward: friend.id) else { return }
        shareTotal = existing.shareTotal
        selectedCategories = Set(existing.shareCategories)
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
