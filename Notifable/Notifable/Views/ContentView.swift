import SwiftUI
import SwiftData

enum AppTab: Int, CaseIterable {
    case home = 0
    case categories = 1
    case social = 2
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .categories: return "tray.full.fill"
        case .social: return "person.3.fill"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Resumen"
        case .categories: return "Categorías"
        case .social: return "Social"
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
    @State private var showAddExpense = false
    @State private var showSplash = true
    @State private var isPulsing = false
    @State private var tabWidth: CGFloat = 0
    
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
                            DashboardView(scrollOffset: $scrollOffset)
                        case .categories:
                            CategoriesView(scrollOffset: $scrollOffset)
                        case .social:
                            SocialView(scrollOffset: $scrollOffset)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Tab Bar Flotante
                    githubFloatingTabBar
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea()) // Fondo global dinámico
            .ignoresSafeArea(.keyboard)
            .onReceive(syncTimer) { _ in
                Task {
                    await SyncManager.shared.syncLocalExpensesToCloud(localExpenses: expenses)
                }
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAddExpense) {
                AddExpenseView()
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
    
    private var topHeader: some View {
        HStack {
            Image(systemName: "bell.badge.fill")
                .font(.title)
                .foregroundStyle(.purple)
            
            // Texto siempre visible
            Text("AgruPay")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(isDarkMode ? .white : .black)
            
            Spacer()
            
            Button {
                withAnimation {
                    isDarkMode.toggle()
                }
            } label: {
                Image(systemName: isDarkMode ? "moon.fill" : "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(isDarkMode ? .yellow : .orange)
            }
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
        .padding(.bottom, 24) // Más grueso
        .background(Color(.systemBackground)) // Mismo color que el fondo, sólido
    }
    
    private var githubFloatingTabBar: some View {
        HStack(spacing: 12) {
            // Barra Izquierda
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                            .frame(width: 48, height: 32)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? Color.blue.opacity(0.3) : Color.clear)
                            )
                        
                        Text(tab.title)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.gray)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle()) // Área clickeable completa
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(.regularMaterial, in: Capsule()) // Correct way to apply material to a shape
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear { tabWidth = geo.size.width / 3 }
                        .onChange(of: geo.size.width) { _, newWidth in tabWidth = newWidth / 3 }
                }
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard tabWidth > 0 else { return }
                        let index = Int(value.location.x / tabWidth)
                        if index >= 0 && index < 3 {
                            let newTab = AppTab(rawValue: index) ?? .home
                            if selectedTab != newTab {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = newTab
                                }
                            }
                        }
                    }
            )
            
            // Barra Derecha (Botón +)
            Button(action: { showAddExpense = true }) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(isDarkMode ? .white : .black)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 70) 
            .background(
                Capsule()
                    .fill(Color.purple.opacity(isDarkMode ? 0.3 : 0.8)) // Morado más intenso en claro
            )
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, -15) // Empujarlo más abajo del límite del SafeArea
        .shadow(color: Color.primary.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Expense.self, inMemory: true)
}
