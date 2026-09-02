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
    @State private var selectedTab: AppTab = .home
    @State private var scrollOffset: CGFloat = 0
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.purple.rawValue
    
    var themeColor: Color { AppThemeColor(rawValue: appAccentColor)?.color ?? .purple }
    @State private var showSettings = false
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var selectedTransactionType: TransactionType? = nil
    @State private var showSplash = true
    @State private var isPulsing = false
    @State private var tabWidth: CGFloat = 0
    @State private var scrollToTopTrigger: Bool = false
    @State private var themeButtonCenter: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 80, y: 60)
    
    let syncTimer = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()
    
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
            
            // El menú previo de elegir Gasto o Ingreso desaparece: el
            // segmentado del propio modal lo resuelve, y así el + hace
            // una sola cosa.
            
            // Splash Screen Overlay
            if showSplash {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(themeColor)
                            .scaleEffect(isPulsing ? 1.1 : 0.9)
                            .opacity(isPulsing ? 1.0 : 0.5)
                        
                        Text("AgruPay")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(isDarkMode ? .white : .black)
                            .opacity(isPulsing ? 1.0 : 0.5)
                    }
                }
                .transition(.opacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                    
                    // Ocultar el splash después de 2 segundos
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            showSplash = false
                        }
                    }
                }
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
    
    // MARK: - Top Header
    private var topHeader: some View {
        HStack {
            Image(systemName: "bell.badge.fill")
                .font(.title)
                .foregroundStyle(themeColor)
            
            Text("AgruPay")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(isDarkMode ? .white : .black)
            
            Spacer()
            
            Button {
                ThemeAnimator.animateThemeChange(from: themeButtonCenter) {
                    isDarkMode.toggle()
                }
            } label: {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(isDarkMode ? .yellow : .orange)
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
                    selectedTransactionType = .gasto
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(isDarkMode ? .white : .black)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(selectedTransactionType != nil ? 45 : 0))
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
