import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recurringRules: [RecurringExpense]
    @AppStorage("remindRecurring") private var remindRecurring = true
    @State private var didResolveRecurring = false
    @State private var selectedTab: AppTab = .summary

    // Sub-vista activa de cada pestaña. Una por pestaña, no una global: al
    // volver a Análisis se espera encontrarlo como se dejó, pero tocar el
    // ícono de la pestaña ya activa devuelve a la sub-vista por defecto.
    @State private var summarySub: SummarySubtab = .today
    @State private var analysisSub: AnalysisSubtab = .categories
    @State private var socialSub: SocialSubtab = .activity

    /// El desplazamiento de la pestaña visible, en una clase observable para
    /// no invalidar este cuerpo en cada fotograma (ver `ScrollProgress`).
    @State private var scrollProgress = ScrollProgress()
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false
    
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
    /// Lo que pidió el último enlace `agrupay://` para el formulario.
    @State private var linkedSource: String?
    @State private var linkedQuickID: UUID?
    /// Un enlace que llegó con la app bloqueada o con el splash: se aplica al
    /// desbloquear, nunca por encima de la pantalla de bloqueo.
    @State private var pendingLink: AppDeepLink?
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

        // Sólo la ventana que el motor necesita para casar cada regla con el
        // cobro que ya llegó del banco. Antes esto venía de un `@Query` sin
        // predicado en la raíz: la app materializaba el historial completo al
        // arrancar —y lo mantenía vivo— para una comprobación que corre una
        // vez por sesión.
        let expenses = recurringExpenses()

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

    /// Los gastos de la ventana de casado de recurrentes. Sin reglas activas
    /// no hay nada que casar y no se pide nada.
    private func recurringExpenses() -> [Expense] {
        guard let window = RecurringEngine.matchWindow(rules: recurringRules) else { return [] }
        let start = window.start
        let end = window.end
        let descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\Expense.date, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Enlaces

    private func applyPendingLinkIfReady() {
        guard let link = pendingLink, !appLock.isLocked, !showSplash else { return }
        pendingLink = nil
        showAddPicker = false
        showSettings = false

        switch link {
        case let .add(isIncome, source):
            presentAdd(isIncome ? .ingreso : .gasto, source: source, quickID: nil)
        case .quick(let id):
            presentAdd(.gasto, source: nil, quickID: id)
        // Los enlaces `agrupay://` de los widgets y de Siri siguen siendo los
        // mismos; lo que cambia es dónde aterrizan. `categories` y `rhythm` ya
        // no son pestañas: ahora son sub-vistas de Análisis.
        case .summary:
            selectedTransactionType = nil
            summarySub = .today
            selectedTab = .summary
        case .categories:
            selectedTransactionType = nil
            analysisSub = .categories
            selectedTab = .analysis
        case .pending:
            selectedTransactionType = nil
            analysisSub = .pending
            selectedTab = .analysis
        case .rhythm:
            selectedTransactionType = nil
            analysisSub = .history
            selectedTab = .analysis
        case .friendInvite(let code):
            selectedTransactionType = nil
            FriendInviteRouter.shared.pendingCode = code
            socialSub = .friends
            selectedTab = .social
        }
    }

    /// Si ya había un formulario abierto se cierra primero: cambiar el
    /// `item` de una hoja presentada no la vuelve a construir.
    private func presentAdd(_ type: TransactionType, source: String?, quickID: UUID?) {
        let open = {
            linkedSource = source
            linkedQuickID = quickID
            selectedTransactionType = type
        }
        if selectedTransactionType != nil {
            selectedTransactionType = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: open)
        } else {
            open()
        }
    }

    var body: some View {
        ZStack {
            // El chrome **flota** sobre el contenido; ya no lo empuja hacia
            // abajo. Por eso es un `ZStack` y no un `VStack`: el monto grande
            // de Resumen pasa por debajo de los botones circulares al hacer
            // scroll, que es lo que permite que el header sea transparente.
            ZStack(alignment: .top) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                header

                // Degradado al pie: las píldoras son de vidrio y sin él las
                // filas se leen a través de ellas. Sube hasta 150 pt y no
                // intercepta toques.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: [Palette(systemScheme).background.opacity(0),
                                            Palette(systemScheme).background],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 150)
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea(edges: .bottom)

                if showAddPicker {
                    AddMenu(onPick: { type in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    showAddPicker = false
                                }
                                presentAdd(type, source: nil, quickID: nil)
                            },
                            onDismiss: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    showAddPicker = false
                                }
                            })
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ShellBottomBar(selection: tabSelection,
                                   progress: scrollProgress,
                                   isAddMenuOpen: showAddPicker,
                                   onReselect: reselect,
                                   onAdd: {
                                       withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                           showAddPicker.toggle()
                                       }
                                   },
                                   onDictate: { presentAdd(.gasto, source: nil, quickID: nil) })
                        .padding(.bottom, 4)
                }
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .ignoresSafeArea(.keyboard)
            .onAppear(perform: resolveRecurring)
            .onChange(of: selectedTab) { _, tab in
                Diagnostics.shared.log("Pestaña: \(tab)")
            }
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
            .sheet(item: $selectedTransactionType, onDismiss: {
                linkedSource = nil
                linkedQuickID = nil
            }) { type in
                AddTransactionSheet(transactionType: type, source: linkedSource, savingQuick: linkedQuickID)
            }
            .onOpenURL { url in
                guard let link = AppDeepLink(url: url) else { return }
                Diagnostics.shared.log("Enlace: \(url.host ?? "")")
                pendingLink = link
                applyPendingLinkIfReady()
            }
            .onChange(of: appLock.isLocked) { _, _ in applyPendingLinkIfReady() }
            .onChange(of: showSplash) { _, _ in applyPendingLinkIfReady() }
            
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
                // Siempre en oscuro (`5l`), sea cual sea el tema: es la
                // pantalla previa a la app, y así no destella al desbloquear.
                LockScreenView(lock: appLock)
                    .environment(\.colorScheme, .dark)
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
            // Oscuro como el bloqueo que tapa: si no, el paso de uno a otro
            // destellaba en claro.
            Palette(.dark).background.ignoresSafeArea()
            AppIconTile(size: 64, accent: themeColor, coinFace: .white, detail: false)
        }
    }

    // MARK: - Contenido de la pestaña

    /// Cada pestaña resuelve su sub-vista. Las diez viven en su propio
    /// archivo y comparten el mismo esqueleto: `TrackableScrollView`, el hueco
    /// del header flotante arriba y el de las píldoras abajo.
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .summary:
            switch summarySub {
            case .today:
                TodayScreen(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            case .movements:
                MovementsView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            case .balance:
                BalanceView(scrollToTopTrigger: $scrollToTopTrigger,
                            progress: scrollProgress,
                            onAddIncome: { presentAdd(.ingreso, source: nil, quickID: nil) })
            }

        case .analysis:
            switch analysisSub {
            case .pending:
                PendingView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            case .categories:
                CategoriesOverviewView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            case .budgets:
                BudgetsView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            case .history:
                HistoryView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            }

        case .social:
            switch socialSub {
            case .activity:
                ActivityView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            case .friends:
                FriendsListView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            case .profile:
                ProfileView(scrollToTopTrigger: $scrollToTopTrigger, progress: scrollProgress)
            }
        }
    }

    // MARK: - Header flotante

    /// Ajustes y tema a la izquierda —fijos en las tres pestañas—, y a la
    /// derecha la píldora de sub-navegación de la pestaña activa.
    ///
    /// Vive en `ShellHeaderBar`, no aquí: es quien lee el desplazamiento, y
    /// esa lectura no puede quedarse en este cuerpo.
    private var header: some View {
        ShellHeaderBar(tab: selectedTab,
                       progress: scrollProgress,
                       summarySub: $summarySub,
                       analysisSub: $analysisSub,
                       socialSub: $socialSub,
                       onSettings: { showSettings = true },
                       onTheme: toggleTheme,
                       onMeasureThemeButton: { themeButtonCenter = $0 })
    }

    // MARK: - Acciones del chrome

    /// Tocar la pestaña ya activa: primero sube al tope, y si ya está arriba
    /// vuelve a su sub-vista por defecto.
    /// La barra inferior escribe aquí y no en `selectedTab` directo: entrar a
    /// Análisis desde la barra abre siempre Categorías. Los enlaces profundos
    /// (Pendientes, Historial) cambian `selectedTab` por su cuenta y conservan
    /// la sub-vista que eligen.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { tab in
                if tab == .analysis, selectedTab != .analysis {
                    analysisSub = .categories
                }
                selectedTab = tab
            }
        )
    }

    private func reselect(_ tab: AppTab) {
        let atTop = scrollProgress.offset < 12
        guard atTop else {
            scrollToTopTrigger.toggle()
            return
        }

        withAnimation(.easeInOut(duration: 0.26)) {
            switch tab {
            case .summary:  summarySub = .today
            case .analysis: analysisSub = .categories
            case .social:   socialSub = .activity
            }
        }
    }

    private func toggleTheme() {
        ThemeAnimator.animateThemeChange(from: themeButtonCenter) {
            appearanceRaw = (systemScheme == .dark ? AppAppearance.light : .dark).rawValue
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Expense.self, inMemory: true)
}
