import SwiftUI
import SwiftData

/// El header flotante montado, con su píldora y sus reglas de visibilidad.
///
/// **Existe para aislar el desplazamiento.** `ScrollProgress` es observable, así
/// que quien lea `progress.offset` se vuelve a dibujar en cada fotograma del
/// scroll. Cuando esa lectura vivía en el cuerpo de `ContentView`, el cuerpo
/// entero —el `switch` de pestañas, la vista visible y el recuento de
/// pendientes sobre todo el historial— se reevaluaba a 120 Hz mientras el dedo
/// se movía. Es el mismo error del que avisa `TrackableScrollView`, y era lo
/// que hacía que la pantalla de entrada se sintiera pesada justo al
/// desplazarse.
///
/// Aquí dentro, lo que se redibuja por fotograma es un header: dos botones, una
/// píldora y un fondo.
struct ShellHeaderBar: View {
    let tab: AppTab
    let progress: ScrollProgress
    @Binding var summarySub: SummarySubtab
    @Binding var analysisSub: AnalysisSubtab
    @Binding var socialSub: SocialSubtab
    let onSettings: () -> Void
    let onTheme: () -> Void
    let onMeasureThemeButton: (CGPoint) -> Void

    /// Sólo los movimientos sin clasificar del mes: es lo que cuenta el badge.
    /// Con predicado, no el historial entero — el badge no puede costar lo que
    /// cuesta cargar años de correo.
    @Query private var unclassified: [Expense]
    /// Uno solo, de cualquier fecha: sólo hay que saber si existe, así que
    /// `fetchLimit = 1` en vez de traer el historial sin clasificar.
    @Query private var anyUnclassified: [Expense]

    @AppStorage(BudgetStore.monthlyBudgetKey) private var monthlyBudget = 0.0
    @AppStorage(BudgetStore.enabledKey) private var budgetEnabled = false
    @StateObject private var categoryBudgets = CategoryBudgetStore.shared

    init(tab: AppTab,
         progress: ScrollProgress,
         summarySub: Binding<SummarySubtab>,
         analysisSub: Binding<AnalysisSubtab>,
         socialSub: Binding<SocialSubtab>,
         onSettings: @escaping () -> Void,
         onTheme: @escaping () -> Void,
         onMeasureThemeButton: @escaping (CGPoint) -> Void) {
        self.tab = tab
        self.progress = progress
        self._summarySub = summarySub
        self._analysisSub = analysisSub
        self._socialSub = socialSub
        self.onSettings = onSettings
        self.onTheme = onTheme
        self.onMeasureThemeButton = onMeasureThemeButton

        let month = Period(granularity: .mes, reference: Date()).interval
        let start = month.start
        let end = month.end
        let unclassifiedName = Accounting.unclassified
        _unclassified = Query(filter: #Predicate<Expense> {
            $0.category == unclassifiedName && $0.date >= start && $0.date < end
        })

        var anyDescriptor = FetchDescriptor<Expense>(predicate: #Predicate<Expense> {
            $0.category == unclassifiedName
        })
        anyDescriptor.fetchLimit = 1
        _anyUnclassified = Query(anyDescriptor)
    }

    /// `3d`: nada vacío se dibuja. Pendientes sólo con movimientos sin
    /// clasificar (de cualquier mes; el badge cuenta sólo los de éste); Balance sólo con un presupuesto definido.
    private var visibility: SubtabVisibility {
        var visibility = SubtabVisibility()
        visibility.pendingCount = Set(unclassified.map(\.merchant)).count
        visibility.hasAnyPending = !anyUnclassified.isEmpty
        visibility.hasBudget = BudgetStore.hasBudget(monthlyBudget: monthlyBudget, enabled: budgetEnabled)
            || categoryBudgets.budgets.contains { $0.value.hasLimit }
        return visibility
    }

    var body: some View {
        let visibility = self.visibility

        ShellHeader(scrollOffset: progress.offset,
                    compactTitle: nil,
                    onSettings: onSettings,
                    onTheme: onTheme) {
            switch tab {
            case .summary:
                SubtabPill(tabs: visibility.summary, selection: $summarySub)
            case .analysis:
                SubtabPill(tabs: visibility.analysis, selection: $analysisSub) { subtab in
                    visibility.badge(for: subtab)
                }
            case .social:
                SubtabPill(tabs: visibility.social, selection: $socialSub)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    let frame = geo.frame(in: .global)
                    // El destello del cambio de tema sale del botón, no del
                    // centro de la pantalla.
                    onMeasureThemeButton(CGPoint(x: frame.minX + 62, y: frame.midY))
                }
            }
        )
    }
}
