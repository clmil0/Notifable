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
        case .trends: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Resumen"
        case .categories: return "Categorías"
        case .trends: return "Tendencias"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var expenses: [Expense]
    @State private var selectedTab: AppTab = .home
    @State private var scrollOffset: CGFloat = 0
    @State private var showSettings = false
    @AppStorage("isDarkMode") private var isDarkMode = true
    @State private var selectedTransactionType: TransactionType? = nil
    @State private var showSplash = true
    @State private var isPulsing = false
    @State private var tabWidth: CGFloat = 0
    @State private var showAddPicker = false
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
                            DashboardView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger)
                        case .categories:
                            CategoriesView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger)
                        case .trends:
                            TrendsView(scrollOffset: $scrollOffset, scrollToTopTrigger: $scrollToTopTrigger)
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
                AddExpenseView(transactionType: type)
            }
            
            // Add Picker Overlay
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
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showAddPicker = false
                                }
                                selectedTransactionType = .gasto
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(.title2)
                                    Text("Gasto")
                                        .font(.caption.bold())
                                }
                                .foregroundStyle(Color.purple)
                                .frame(width: 70, height: 60)
                            }
                            
                            Divider().frame(height: 40)
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showAddPicker = false
                                }
                                selectedTransactionType = .ingreso
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.down.left.circle.fill")
                                        .font(.title2)
                                    Text("Ingreso")
                                        .font(.caption.bold())
                                }
                                .foregroundStyle(Color.green)
                                .frame(width: 70, height: 60)
                            }
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
            
            // Splash Screen Overlay
            if showSplash {
                ZStack {
                    Color(.systemBackground).ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.purple)
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
                .foregroundStyle(.purple)
            
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
                                        .fill(selectedTab == tab ? Color.purple.opacity(0.25) : Color.clear)
                                )
                            
                            Text(tab.title)
                                .font(.system(size: 11, weight: selectedTab == tab ? .bold : .regular))
                        }
                        .foregroundStyle(selectedTab == tab ? Color.purple : Color.gray)
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
                    showAddPicker = true
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(isDarkMode ? .white : .black)
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
