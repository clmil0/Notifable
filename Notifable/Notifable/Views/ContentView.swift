import SwiftUI
import SwiftData

enum AppTab: Int, CaseIterable {
    case home = 0
    case categories = 1
    case trends = 2
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .categories: return "tray.full.fill"
        case .trends: return "chart.bar.fill"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Resumen"
        case .categories: return "Categorías"
        case .trends: return "Ritmo"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @Query private var recurringRules: [RecurringExpense]
    @AppStorage("remindRecurring") private var remindRecurring = true
    @State private var didResolveRecurring = false
    @State private var selectedTab: AppTab = .home
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    @State private var showSettings = false
    /// El tema tiene tres estados; el botón de la cabecera alterna entre claro
    /// y oscuro sobre el que se esté viendo, y "Automático" se elige en Ajustes.
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @State private var selectedTransactionType: TransactionType? = nil
    @State private var showAddPicker = false
    @State private var showSplash = true
    @State private var tabWidth: CGFloat = 0
    @State private var scrollToTopTrigger: Bool = false
    @State private var themeButtonCenter: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 80, y: 60)
    
    let syncTimer = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()
    
    /// Aplica las reglas con `autoConfirm` y programa el aviso de las que
    /// esperan confirmación. Una vez por sesión.
    private func resolveRecurring() {
        guard !didResolveRecurring else { return }
        didResolveRecurring = true

        RecurringEngine.applyAutomatic(rules: recurringRules, expenses: expenses, in: modelContext)
        try? modelContext.save()

        let awaiting = RecurringEngine.pending(rules: recurringRules, expenses: expenses)
            .filter(\.isAwaiting)
        let count = awaiting.reduce(0) { $0 + $1.dates.count }
        let total = Money.sum(awaiting) { $0.totalAmount }
        NotificationManager.shared.updateRecurringReminder(
            count: count,
            total: total,
            merchant: awaiting.first.map { Accounting.displayName($0.merchant) },
            enabled: remindRecurring
        )
    }

    /// Cada opción cierra el menú y abre su propio modal.
    private func addOption(title: String, icon: String, tint: Color, type: TransactionType) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showAddPicker = false
            }
            selectedTransactionType = type
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption.bold())
            }
            .foregroundStyle(tint)
            .frame(width: 70, height: 60)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header siempre visible arriba
                topHeader
                
                // Contenido Principal
                ZStack(alignment: .bottom) {
                    Group {
                        switch selectedTab {
                        case .home:
                            DashboardView(onOpenInbox: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedTab = .categories
                                }
                            }, scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger)
                        case .categories:
                            CategoriesView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger)
                        case .trends:
                            RhythmView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Floating Glass Tab Bar (WhatsApp/Telegram style)
                    floatingGlassTabBar
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .ignoresSafeArea(.keyboard)
            .onAppear(perform: resolveRecurring)
            .onReceive(syncTimer) { _ in
                Task {
                    await SyncManager.shared.syncLocalExpensesToCloud(localExpenses: expenses)
                }
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $selectedTransactionType) { type in
                AddTransactionSheet(transactionType: type)
            }
            
            // Botones flotantes de Gasto e Ingreso al tocar el +.
            if showAddPicker {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showAddPicker = false
                        }
                    }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        HStack(spacing: 0) {
                            addOption(title: "Gasto",
                                      icon: "arrow.up.right.circle.fill",
                                      tint: themeColor,
                                      type: .gasto)

                            Divider().frame(height: 40)

                            addOption(title: "Ingreso",
                                      icon: "arrow.down.left.circle.fill",
                                      tint: .green,
                                      type: .ingreso)
                        }
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 90)
                    .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }

            
            // Splash Screen Overlay: la gota a gota de "Icono y Splash" (handoff
            // de identidad) — reemplaza el placeholder de la campanita.
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
            }
        }
    }
    
    // MARK: - Top Header
    private var topHeader: some View {
        HStack {
            AppIconTile(size: 34, coinFace: .white, detail: false)

            Text("AgruPay")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(Color.primary)
            
            Spacer()
            
            Button {
                ThemeAnimator.animateThemeChange(from: themeButtonCenter) {
                    appearanceRaw = (systemScheme == .dark ? AppAppearance.light : .dark).rawValue
                }
            } label: {
                Image(systemName: systemScheme == .dark ? "moon.fill" : "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(systemScheme == .dark ? .yellow : .orange)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            let frame = geo.frame(in: .global)
                            themeButtonCenter = CGPoint(x: frame.midX, y: frame.midY)
                        }
                }
            )
            .padding(.trailing, 8)
            
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Floating Glass Tab Bar (WhatsApp / Telegram style)
    private var floatingGlassTabBar: some View {
        HStack(spacing: 12) {
            // Tab bar principal con glass material
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        if selectedTab == tab {
                            scrollToTopTrigger.toggle()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = tab
                            }
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 22, weight: selectedTab == tab ? .semibold : .regular))
                                .frame(width: 52, height: 32)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? themeColor.opacity(0.25) : Color.clear)
                                )
                            
                            Text(tab.title)
                                .font(.system(size: 11, weight: selectedTab == tab ? .bold : .regular))
                        }
                        .foregroundStyle(selectedTab == tab ? themeColor : Color.gray)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 8)
            
            // Botón + separado (como el de búsqueda en WhatsApp)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showAddPicker.toggle()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(Color.primary)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(showAddPicker ? 45 : 0))
            }
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Expense.self, inMemory: true)
}
