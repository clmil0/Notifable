import SwiftUI

/// Ajustes › Estadísticas: qué tiras salen en el dashboard y en qué orden.
///
/// Cuántas elijas cambia el dibujo, y la vista previa de arriba lo enseña:
/// una sola va en grande con su gráfico, dos se reparten la fila, tres la
/// llenan y con más la fila se vuelve carrusel.
struct StatsSettingsView: View {

    @AppStorage(DashboardStatsSettings.key) private var raw = DashboardStatsSettings.defaultValue
    @AppStorage(AppThemeColor.storageKey) private var appAccentColor = AppThemeColor.blue.rawValue
    @Environment(\.colorScheme) private var scheme

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }

    private var chosen: [DashboardStat] { DashboardStatsSettings.decode(raw) }
    private var hidden: [DashboardStat] { DashboardStat.allCases.filter { !chosen.contains($0) } }

    var body: some View {
        let chosen = self.chosen
        let hidden = self.hidden

        List {
            Section {
                preview(count: chosen.count)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            } footer: {
                Text(layoutNote(count: chosen.count))
            }

            Section {
                if chosen.isEmpty {
                    Text("Ninguna: el dashboard no enseña estadísticas.")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondaryLabel)
                } else {
                    ForEach(chosen) { stat in
                        row(stat, isOn: true)
                    }
                    .onMove(perform: move)
                }
            } header: {
                Text("En el dashboard · \(chosen.count)")
            } footer: {
                Text("Arrastra para cambiar el orden. Neto sólo sale si registras ingresos; Ritmo, con presupuesto; Límites superados, si alguna categoría tiene límite.")
            }

            if !hidden.isEmpty {
                Section("Ocultas") {
                    ForEach(hidden) { stat in
                        row(stat, isOn: false)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Estadísticas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Restablecer") {
                    withAnimation { raw = DashboardStatsSettings.defaultValue }
                }
                .disabled(raw == DashboardStatsSettings.defaultValue)
            }
        }
        .tint(accent.onSurface(scheme))
    }

    // MARK: Filas

    private func row(_ stat: DashboardStat, isOn: Bool) -> some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemName: stat.icon, tint: isOn ? accent.color : Color(white: 0.45))

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.title)
                    .foregroundStyle(palette.label)
                Text(stat.summary)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(get: { isOn }, set: { toggle(stat, on: $0) }))
                .labelsHidden()
                .tint(accent.color)
                .accessibilityLabel(stat.title)
        }
        .padding(.vertical, 2)
        .moveDisabled(!isOn)
    }

    private func toggle(_ stat: DashboardStat, on: Bool) {
        var list = chosen
        if on {
            guard !list.contains(stat) else { return }
            list.append(stat)
        } else {
            list.removeAll { $0 == stat }
        }
        withAnimation(.easeInOut(duration: 0.22)) { raw = DashboardStatsSettings.encode(list) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = chosen
        list.move(fromOffsets: source, toOffset: destination)
        raw = DashboardStatsSettings.encode(list)
    }

    // MARK: Vista previa

    private func layoutNote(count: Int) -> String {
        switch count {
        case 0:  return "Sin estadísticas elegidas, la sección no aparece."
        case 1:  return "Con una sola, ocupa la fila entera con su gráfico, su frase y sus dos cifras."
        case 2:  return "Con dos, se reparten la fila y cada una enseña una segunda línea."
        case 3:  return "Con tres, llenan la fila."
        default: return "Con más de tres, la fila se desliza como carrusel: se ven tres a la vez."
        }
    }

    /// Un esquema del dashboard con tantas tiras como elegiste.
    @ViewBuilder
    private func preview(count: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        switch count {
        case 0:
            shape.strokeBorder(palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 44)
        case 1:
            VStack(alignment: .leading, spacing: 6) {
                bar(width: 70)
                bar(width: 130, height: 12)
                previewChart
                HStack(spacing: 6) { block(); block() }
            }
            .padding(10)
            .background(palette.selectedFill.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case 2:
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 5) {
                        bar(width: 40); bar(width: 70, height: 12); bar(width: 55)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.selectedFill.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        default:
            HStack(spacing: 8) {
                ForEach(0..<min(count, 3), id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 5) {
                        bar(width: 34); bar(width: 50, height: 12)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.selectedFill.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if count > 3 {
                    // La siguiente asomando: se nota que se desliza.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.selectedFill.opacity(0.3))
                        .frame(width: 18, height: 48)
                }
            }
        }
    }

    private func block() -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.selectedFill).frame(height: 24)
    }

    private func bar(width: CGFloat, height: CGFloat = 7) -> some View {
        Capsule().fill(palette.tertiaryLabel.opacity(0.45)).frame(width: width, height: height)
    }

    private var previewChart: some View {
        Path { p in
            let points: [CGFloat] = [0.9, 0.8, 0.82, 0.6, 0.55, 0.4, 0.38, 0.2]
            for (k, y) in points.enumerated() {
                let point = CGPoint(x: CGFloat(k) / CGFloat(points.count - 1) * 240, y: y * 30)
                k == 0 ? p.move(to: point) : p.addLine(to: point)
            }
        }
        .stroke(accent.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 240, height: 30, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
