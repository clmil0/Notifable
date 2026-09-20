import SwiftUI

/// El ícono de un movimiento en el lenguaje nuevo: cuadrado redondeado de
/// 44 pt (radio 13) con el color de la categoría al 18 % y el símbolo al 100 %.
///
/// Sustituye al círculo de 48 pt de `DashboardView`. El cuadrado redondeado
/// alinea con el radio de las tarjetas (22) y con el de los cuadros de
/// categoría del resto del rediseño; el círculo se queda para los avatares de
/// personas, que es donde sí significa algo distinto.
struct MovementIcon: View {
    let icon: String
    let color: Color
    var size: CGFloat = 44

    @Environment(\.colorScheme) private var scheme

    /// Los íconos de billetera y banco son imágenes de marca: no se tiñen.
    private var isAsset: Bool {
        ["plin_icon", "yape_icon", "bbva_icon"].contains(icon)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.295, style: .continuous)
                .fill(color.opacity(scheme == .dark ? 0.22 : 0.18))

            if isAsset {
                Image(icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size * 0.55, height: size * 0.55)
                    .clipShape(Circle())
            } else {
                Image(systemName: icon)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Ícono y color de un gasto. Extraído de `DashboardView` para que la fila
/// nueva y la antigua no se separen mientras conviven.
enum MovementStyle {

    static func icon(for expense: Expense) -> String {
        if expense.merchant.hasPrefix("PLIN - ") { return "plin_icon" }
        if expense.merchant.hasPrefix("YAPE - ") { return "yape_icon" }
        if expense.merchant.hasPrefix("BBVA - ") { return "bbva_icon" }
        if expense.merchant.lowercased().contains("apple") { return "applelogo" }
        return CategoryStyle.icon(for: expense.category)
    }

    static func color(for expense: Expense, accent: Color, scheme: ColorScheme) -> Color {
        if expense.merchant.hasPrefix("PLIN - ") { return Color(red: 0, green: 0.7, blue: 0.9) }
        if expense.merchant.hasPrefix("YAPE - ") { return Color(red: 0.5, green: 0, blue: 0.5) }
        if expense.merchant.hasPrefix("BBVA - ") { return Color(red: 0.0, green: 0.27, blue: 0.51) }
        if expense.merchant.lowercased().contains("apple") { return scheme == .dark ? .white : .black }
        return CategoryStyle.color(for: expense.category, accent: accent)
    }

    /// El origen del movimiento para el subtítulo: la billetera con la que se
    /// pagó o la tarjeta. No se inventa "Efectivo" cuando no se sabe: si el
    /// correo no dijo de dónde salió el dinero, el subtítulo es sólo la
    /// categoría.
    static func source(for expense: Expense) -> String? {
        if expense.merchant.hasPrefix("PLIN - ") { return "Plin" }
        if expense.merchant.hasPrefix("YAPE - ") { return "Yape" }
        if expense.merchant.hasPrefix("BBVA - ") { return "BBVA" }
        if let card = expense.cardLastDigits, !card.isEmpty { return "•••• " + card }
        return nil
    }
}

/// Una fila de la lista de Hoy: ícono, comercio, `Categoría · Origen`, monto.
///
/// Sin categoría, el subtítulo se cambia por un chip de «Asignar categoría»:
/// clasificar es la acción que la app más necesita del usuario, y esconderla
/// tras una pulsación larga es lo que llenó la bandeja de Pendientes.
struct MovementRow: View {
    let expense: Expense
    var onTap: () -> Void = {}
    var onAssignCategory: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @State private var confirmsDelete = false
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    private var isUnclassified: Bool {
        expense.category == Accounting.unclassified
    }

    /// Un gasto marcado «por cobrar», o con abonos ya recibidos. La fila no
    /// cambia de color por eso —eso volvía la lista un semáforo—, sólo añade
    /// una línea que dice cuánto falta.
    private var debtNote: String? {
        let paid = Accounting.paid(of: expense)
        let outstanding = Accounting.outstanding(of: expense)
        guard expense.isDebt || expense.debtSettled || Money.cents(paid) > 0 else { return nil }
        if expense.debtSettled && !expense.isDebt { return "Deuda saldada" }
        if Money.isZero(outstanding) { return "Cobrado" }
        return "Por cobrar · falta " + Money.format(outstanding, currency: expense.currency)
    }

    var body: some View {
        HStack(spacing: 12) {
            MovementIcon(icon: MovementStyle.icon(for: expense),
                         color: MovementStyle.color(for: expense, accent: accent.color, scheme: scheme))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Accounting.displayName(expense.merchant))
                        .font(.system(size: 16.5, weight: .semibold))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)

                    if expense.isSubscription {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(accent.color)
                    }
                }

                if isUnclassified {
                    // `ViewThatFits`: con un comercio de nombre corto entran
                    // el chip y el origen; con uno largo, el origen se retira
                    // entero en vez de quedarse en unos puntos suspensivos que
                    // no dicen nada. El chip nunca se encoge: es la acción.
                    ViewThatFits(in: .horizontal) {
                        assignRow(showsSource: true)
                        assignRow(showsSource: false)
                    }
                } else {
                    subtitleLine
                }

                if let debtNote {
                    Text(debtNote)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(expense.debtSettled && !expense.isDebt ? palette.positive : palette.warning)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(amountText)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(palette.label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button {
                // El menú se cierra con su propia animación y con la fila
                // levantada en un overlay aparte: mutar aquí hace crecer la
                // fila real por debajo de ese overlay y lo que se ve al
                // aterrizar es un salto ya consumado.
                let expense = expense
                let context = modelContext
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    expense.toggleDebt(in: context)
                }
            } label: {
                Label(expense.isDebt ? "Ya no es por cobrar" : "Por cobrar",
                      systemImage: "exclamationmark.circle")
            }

            Button {
                onAssignCategory()
            } label: {
                Label("Categorizar", systemImage: "tag")
            }

            // Se confirma aparte: el menú se abre con una pulsación larga y
            // un toque de más no debería bastar para perder un movimiento.
            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
        .confirmationDialog("¿Eliminar movimiento?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                let expense = expense
                let context = modelContext
                withAnimation(.easeInOut(duration: 0.25)) {
                    expense.deleteRecordingRecovery(in: context)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borrará de tus cuentas. Esto no se puede deshacer.")
        }
    }

    /// La fila de «sin categoría», con o sin el origen del movimiento.
    private func assignRow(showsSource: Bool) -> some View {
        HStack(spacing: 5) {
            Button(action: onAssignCategory) {
                Text("Asignar categoría")
                    .font(.system(size: 11, weight: .semibold))
                    .fixedSize()
                    .foregroundStyle(accent.onSurface(scheme))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accent.color.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)

            if showsSource, let source = MovementStyle.source(for: expense) {
                Text(source)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize()
            }
        }
    }

    /// «Salud · ●madre +2» cuando el movimiento lleva etiqueta; si no, el
    /// «Categoría · Origen» de siempre.
    ///
    /// La etiqueta **desplaza al origen**, no se añade: en una línea de 12.5 pt
    /// no caben las dos cosas, y saber que el gasto es de tu madre dice más que
    /// saber que llegó por Yape —que además ya se ve en el ícono—. El punto de
    /// color es lo único que la distingue de la categoría, que va en gris y
    /// sin punto.
    @ViewBuilder
    private var subtitleLine: some View {
        if let tag = expense.tags.first {
            HStack(spacing: 5) {
                Text(expense.category + " ·")
                    .foregroundStyle(palette.secondaryLabel)

                Circle()
                    .fill(TagCatalog.shared.color(for: tag))
                    .frame(width: 7, height: 7)

                Text(tag)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                if expense.tags.count > 1 {
                    Text("+\(expense.tags.count - 1)")
                        .foregroundStyle(palette.secondaryLabel)
                        .fixedSize()
                }
            }
            .font(.system(size: 12.5))
        } else {
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondaryLabel)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        if let source = MovementStyle.source(for: expense) {
            return expense.category + " · " + source
        }
        return expense.category
    }

    /// El guion es un menos tipográfico (U+2013), no un guion de teclado: a
    /// 16.5 pt semibold el guion corto se lee como parte del número.
    private var amountText: String {
        let paid = Accounting.paid(of: expense)
        let outstanding = Accounting.outstanding(of: expense)
        let displayed = (expense.isDebt || Money.cents(paid) > 0) ? outstanding : expense.amount
        return "–" + Money.format(displayed, currency: expense.currency)
    }
}

/// Fila de ingreso, con el mismo esqueleto que la de gasto.
struct IncomeRow: View {
    let income: Income
    var onTap: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @State private var showsDestino = false
    @State private var confirmsDelete = false
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    var body: some View {
        let (color, icon) = IncomeStyle.iconAndColor(for: income, accent: accent.incomeFillColor)

        HStack(spacing: 12) {
            MovementIcon(icon: icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(income.title ?? income.source)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                Text(income.source)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("+" + Money.format(income.amount, currency: income.currency))
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(accent.incomeColor(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button {
                showsDestino = true
            } label: {
                Label("Asignar a deuda", systemImage: "scope")
            }

            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
        // Desde la hoja se puede ir a la deuda (`ActivityFocus`): se cierra
        // para que Hoy la muestre.
        .onReceive(NotificationCenter.default.publisher(for: ActivityFocus.notification)) { _ in
            showsDestino = false
        }
        // La misma hoja que «¿A dónde va?» en el detalle del ingreso.
        .sheet(isPresented: $showsDestino) {
            IncomeDestinoSheet(income: income)
        }
        .confirmationDialog("¿Eliminar este ingreso?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                let income = income
                let context = modelContext
                withAnimation(.easeInOut(duration: 0.25)) {
                    income.deleteRestoringDebt(in: context)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(income.debtReference != nil
                 ? "Se borrará de tus cuentas y lo que devuelve volverá a figurar como pendiente. Esto no se puede deshacer."
                 : "Se borrará de tus cuentas. Esto no se puede deshacer.")
        }
    }
}

/// La tarjeta que agrupa las filas de un día: radio 22, superficie con
/// hairline y separadores internos sangrados 70 pt —el ancho del ícono más su
/// margen—, para que la línea arranque bajo el texto y no bajo el ícono.
struct MovementCard<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
    }
}

struct MovementSeparator: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(Palette(scheme).separator)
            .frame(height: 0.5)
            .padding(.leading, 70)
    }
}
