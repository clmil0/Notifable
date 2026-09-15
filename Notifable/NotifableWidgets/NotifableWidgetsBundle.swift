import SwiftUI
import WidgetKit

/// Los widgets de AgruPay. Todos leen `WidgetSnapshot` del App Group; ninguno
/// abre la base de datos.
@main
struct NotifableWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PaceWidget()
        TodayWidget()
        CategoriesWidget()
        CategoryLimitWidget()
        QuickAddWidget()
        MonthPanelWidget()
    }
}
