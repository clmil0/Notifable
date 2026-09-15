import SwiftUI

/// La barra de periodo más el scrubber de días, que es lo que va arriba de las
/// tres pestañas. Se agrupan aquí para que las dos compartan la memoria de
/// "¿de qué granularidad vengo?" al entrar y salir de un día.
struct PeriodHeader: View {

    /// Ajustes › A tu medida. Encendido, la `PeriodBar` sale del scroll y se
    /// queda fija arriba (ver `.pinnedPeriodBar`); aquí sólo queda el scrubber.
    static let pinnedBarKey = "periodBarPinned"

    @Binding var period: Period
    @AppStorage(PeriodHeader.pinnedBarKey) private var pinsBar = true
    /// Gasto por día de cualquier periodo. La vista lo resuelve con
    /// `Accounting.totals`; el scrubber lo pide para el periodo que dibuja, que
    /// no siempre es el visible (al entrar a un día sigue mostrando su mes).
    let dailySpent: (Period) -> [PeriodTotals.DayTotal]

    @State private var returnGranularity: PeriodGranularity?

    /// El periodo que dibuja el scrubber: el visible, o el que lo contiene
    /// cuando se ha entrado a un día concreto.
    private var scrubberPeriod: Period? {
        switch period.granularity {
        case .mes, .semana:
            return period
        case .dia:
            guard let origin = returnGranularity else { return nil }
            var parent = period
            parent.granularity = origin
            return parent
        case .anio, .rango:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if !pinsBar {
                PeriodBar(period: $period)
            }

            if let scrubberPeriod {
                DayScrubber(period: $period,
                            returnGranularity: $returnGranularity,
                            dailySpent: dailySpent(scrubberPeriod))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: period.granularity)
    }
}

/// Coloca la `PeriodBar` fija sobre el scroll de la pestaña cuando el ajuste
/// está encendido. Va en el `ScrollView` de Resumen, Categorías y Ritmo, junto
/// al `PeriodHeader` que deja de dibujarla.
private struct PinnedPeriodBar: ViewModifier {

    @Binding var period: Period
    @AppStorage(PeriodHeader.pinnedBarKey) private var pinsBar = true

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if pinsBar {
                PeriodBar(period: $period)
                    .padding(.bottom, 8)
                    .background(Color(.systemBackground))
            }
        }
    }
}

extension View {
    func pinnedPeriodBar(period: Binding<Period>) -> some View {
        modifier(PinnedPeriodBar(period: period))
    }
}
