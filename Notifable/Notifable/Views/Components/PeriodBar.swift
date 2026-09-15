import SwiftUI

/// Una sola fila de 34 pt para todo el control de periodo.
///
/// ```
/// [ ‹ 34×34 ] [  Título flexible, .headline  ] [ › 34×34 ] [ Mes ▾ ]
/// ```
///
/// Sustituye a las tres filas apiladas anteriores: los 4 chips de filtro, las
/// flechas y los subfiltros por día/semana/mes de `DateNavigatorView`.
struct PeriodBar: View {

    @Binding var period: Period

    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    @AppStorage(AppThemeColor.intenseTintKey) private var intenseThemeTint = false

    @State private var showRangePicker = false
    @State private var showGranularityPicker = false
    @State private var draftStart = Date()
    @State private var draftEnd = Date()

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .purple }
    private var palette: Palette { Palette(scheme) }

    private let height: CGFloat = 34
    private let radius: CGFloat = 10

    var body: some View {
        HStack(spacing: 8) {
            arrow(systemName: "chevron.left", forward: false)

            Text(period.title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(surface)
                .contentTransition(.numericText())

            arrow(systemName: "chevron.right", forward: true)

            granularityChip
        }
        // Aquí y no en el chip: el título de al lado tiene que ceder o ganar
        // ancho con el mismo muelle, también cuando la granularidad cambia
        // desde fuera (entrar a un día desde el scrubber).
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: period.granularity)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard abs(value.translation.width) > 30 else { return }
                    if value.translation.width > 0 {
                        go(forward: false)
                    } else if period.canGoForward {
                        go(forward: true)
                    }
                }
        )
        .sheet(isPresented: $showRangePicker) {
            rangeSheet
        }
    }

    // MARK: - Piezas

    private var surface: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 0.5)
            )
    }

    private func arrow(systemName: String, forward: Bool) -> some View {
        let enabled = forward ? period.canGoForward : true
        return Button {
            go(forward: forward)
        } label: {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.label)
                .frame(width: height, height: height)
                .background(surface)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(forward ? "Periodo siguiente" : "Periodo anterior")
    }

    /// Un botón con popover propio, no un `Menu`.
    ///
    /// Con `Menu`, iOS anima el cierre fundiendo el contenido del menú
    /// ("Semana ✓") de vuelta sobre la etiqueta: con el chip dibujado aparte,
    /// se veían dos imágenes mezcladas y el chip parpadeaba. Y con el chip
    /// como etiqueta del `Menu`, el ancho no se animaba y saltaba de golpe. El
    /// popover no toca el chip: sólo su ancho crece o se recoge con el muelle
    /// de la barra.
    private var granularityChip: some View {
        Button {
            showGranularityPicker = true
        } label: {
            HStack(spacing: 4) {
                Text(period.granularity.shortLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize()
                    // Sin transformar las letras: el texto cambia de una vez y
                    // sólo el ancho se anima.
                    .contentTransition(.identity)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(accent.onSurface(scheme))
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(accent.softFill(scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(intenseThemeTint ? Color.clear : accent.color.opacity(0.5), lineWidth: 0.5)
                    )
            )
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Granularidad del periodo")
        .accessibilityValue(period.granularity.rawValue)
        .popover(isPresented: $showGranularityPicker, arrowEdge: .top) {
            granularityList
                .presentationCompactAdaptation(.popover)
        }
    }

    private var granularityList: some View {
        VStack(spacing: 0) {
            ForEach(Array(PeriodGranularity.allCases.enumerated()), id: \.element) { index, g in
                Button {
                    showGranularityPicker = false
                    select(g)
                } label: {
                    HStack(spacing: 12) {
                        Text(g.rawValue)
                            .foregroundStyle(palette.label)
                        Spacer(minLength: 16)
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent.color)
                            .opacity(period.granularity == g ? 1 : 0)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < PeriodGranularity.allCases.count - 1 {
                    Rectangle().fill(palette.separator).frame(height: 0.5)
                        .padding(.leading, 16)
                }
            }
        }
        .frame(width: 180)
    }

    private var rangeSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Selecciona el rango de fechas")) {
                    DatePicker("Desde", selection: $draftStart, in: ...draftEnd, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    DatePicker("Hasta", selection: $draftEnd, in: draftStart..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }
            .navigationTitle("Rango de Fechas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showRangePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        period.granularity = .rango
                        period.customStart = draftStart
                        period.customEnd = draftEnd
                        showRangePicker = false
                    }
                }
            }
        }
        .presentationDetents([.fraction(0.4)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Acciones

    private func go(forward: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            period = forward ? period.next : period.previous
        }
    }

    private func select(_ g: PeriodGranularity) {
        if g == .rango {
            draftStart = period.customStart
            draftEnd = period.customEnd
            // Espera a que se cierre el popover: presentar una hoja mientras
            // otra presentación se retira hace que iOS la ignore.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showRangePicker = true
            }
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            var updated = period
            updated.granularity = g
            // Al cambiar de granularidad se vuelve al periodo que contiene hoy,
            // salvo que el usuario estuviera navegando el pasado.
            if !updated.contains(period.reference) {
                updated.reference = period.reference
            }
            if updated.interval.start > Date() {
                updated.reference = Date()
            }
            period = updated
        }
    }
}
