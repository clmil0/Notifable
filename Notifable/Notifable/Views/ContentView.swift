import SwiftUI
import SwiftData

enum AppTab: Int, CaseIterable {
    case home = 0
    case categories = 1
    case trends = 2
    case amigos = 3
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .categories: return "tray.full.fill"
        case .trends: return "chart.bar.fill"
        case .amigos: return "person.2.fill"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Resumen"
        case .categories: return "Categorías"
        case .trends: return "Ritmo"
        case .amigos: return "Amigos"
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
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    /// En `AppStorage` porque el banner de Resumen necesita dejarlo en
    /// Pendientes antes de navegar hasta Categorías (`onOpenInbox`); por eso
    /// sobrevive de por sí a cambiar de pestaña. Tocar el ícono de Categorías
    /// desde la barra inferior, en cambio, siempre debe abrir Mis Categorías
    /// — nunca dejarte donde estabas la última vez.
    @AppStorage("categoriesSegment") private var categoriesSegment = CategoryTab.misCategorias
    
    var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    var themeColor: Color { accent.color }
    @State private var showSettings = false

    /// Red de seguridad de la cadena de vinculación: normalmente la presenta
    /// `SettingsView`, pero si la app se cerró a medias —o el token llegó ya
    /// fuera de Ajustes— la pregunta sigue pendiente y hay que hacerla igual.
    /// Sólo con Ajustes cerrado: dos `fullScreenCover` a la vez no se pueden.
    /// El tema tiene tres estados; el botón de la cabecera alterna entre claro
    /// y oscuro sobre el que se esté viendo, y "Automático" se elige en Ajustes.
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @State private var selectedTransactionType: TransactionType? = nil
    @State private var showAddPicker = false
    @State private var showSplash = true
    @StateObject private var appLock = AppLock.shared
    @State private var tabWidth: CGFloat = 0
    @State private var scrollToTopTrigger: Bool = false
    @State private var themeButtonCenter: CGPoint = CGPoint(x: UIScreen.main.bounds.width - 80, y: 60)
    
    
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
                            }, scrollToTopTrigger: $scrollToTopTrigger)
                        case .categories:
                            CategoriesView(scrollToTopTrigger: $scrollToTopTrigger)
                        case .trends:
                            RhythmView(scrollToTopTrigger: $scrollToTopTrigger)
                        case .amigos:
                            AmigosHubView(scrollToTopTrigger: $scrollToTopTrigger)
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
            .onChange(of: appLock.isLocked) { _, locked in
                // Ajustes y las hojas se presentan en la capa de modales de
                // iOS, por encima de este `ZStack`: si quedaran abiertas, la
                // pantalla de bloqueo estaría **detrás** de ellas y no taparía
                // nada. Bloquear cierra lo que hubiera encima.
                guard locked else { return }
                showSettings = false
                selectedTransactionType = nil
                showAddPicker = false
            }
            .gmailLinkFlow(isEnabled: !showSettings)
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
                                      tint: accent.incomeColor,
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

            
            // Blindaje instantáneo: montado siempre, sin `.task` ni
            // transición — sólo cambia opacidad. `LockScreenView` reacciona a
            // `appLock.isLocked` a través de `@Published`, y SwiftUI puede
            // tardar un fotograma en montarla la primera vez; si ese
            // fotograma justo coincide con el que iOS fotografía para el
            // conmutador de apps (lo típico es pasar a segundo plano al
            // toque de haber desbloqueado, con la vista recién reconstruida),
            // el contenido de verdad queda expuesto ahí. Esta capa, al no
            // tener que montarse desde cero, sólo cambia una opacidad sobre
            // una vista que ya existe — lo que sí alcanza a dibujarse a
            // tiempo — y cubre mientras la pantalla interactiva llega.
            privacyShield
                .opacity(appLock.isLocked ? 1 : 0)
                .allowsHitTesting(false)
                .animation(nil, value: appLock.isLocked)
                .zIndex(9)

            // La puerta va por encima de todo lo de esta pantalla, y por
            // debajo del splash: al abrir se ve primero la marca y luego el
            // bloqueo, no los dos peleándose.
            if appLock.isLocked {
                LockScreenView(lock: appLock)
                    .transition(.opacity)
                    .zIndex(10)
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
    
    // MARK: - Blindaje de privacidad

    /// Fondo + ícono, nada interactivo. A propósito no es `LockScreenView`:
    /// esa arranca Face ID en `.task` al aparecer, y esta vista está montada
    /// todo el tiempo — dispararía el diálogo del sistema con la app en
    /// segundo plano. Sólo tapa hasta que la pantalla de verdad llega.
    private var privacyShield: some View {
        ZStack {
            Palette(systemScheme).background.ignoresSafeArea()
            AppIconTile(size: 64, accent: themeColor, coinFace: .white, detail: false)
        }
    }

    // MARK: - Top Header
    private var topHeader: some View {
        HStack {
            Button {
                withAnimation {
                    selectedTab = .home
                }
            } label: {
                HStack(spacing: 8) {
                    AppIconTile(size: 34, accent: themeColor, coinFace: .white, detail: false)

                    Text("AgruPay")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.primary)
                }
            }
            
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
                            if tab == .categories {
                                categoriesSegment = .misCategorias
                            }
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
