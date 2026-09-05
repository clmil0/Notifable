import SwiftUI
import SwiftData

/// Último paso: desde cuándo leer el correo.
///
/// Se pregunta aquí y no después porque la primera lectura define lo que el
/// usuario ve al abrir la app. Leer un año entero en la primera apertura tarda
/// y llena la pantalla de movimientos viejos; leer un mes deja la app útil en
/// segundos. Que lo elija él evita las dos decepciones.
///
/// "No leer mis correos" también es una respuesta válida: la app sirve igual
/// anotando a mano, y forzar la lectura para poder entrar sería cobrar un
/// peaje que no hace falta.
struct OnboardingHistoryView: View {

    /// `false` cuando entró sin cuenta: entonces esta pantalla ni se presenta,
    /// pero el parámetro deja explícito de qué caso viene.
    let usesGmail: Bool
    /// `monthsLabel` es `nil` cuando eligió no leer nada: quien llama sabe así
    /// si tiene que enseñar la pantalla de progreso o entrar directo.
    let onDone: (_ monthsLabel: String?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue
    /// La misma clave que usa Gmail y bancos: lo que elija aquí es lo que verá
    /// por defecto la próxima vez que lea correo.
    @AppStorage("readPeriodMonths") private var readPeriodMonths = 3

    @State private var showsCustom = false
    @State private var isStarting = false

    private var accent: AppThemeColor { AppThemeColor(rawValue: appAccentColor) ?? .blue }
    private var palette: Palette { Palette(scheme) }

    private static let standardPeriods = [1, 3, 6, 12]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(accent.color.opacity(0.16))
                        .frame(width: 78, height: 78)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(accent.onSurface(scheme))
                }
                .padding(.top, 56)

                Text("¿Cuánto correo miramos?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(palette.label)
                    .multilineTextAlignment(.center)
                    .padding(.top, 18)

                Text("AgruPay leerá los avisos de tu banco desde la fecha que elijas para armar tu historial. Puedes cambiarlo o ampliarlo cuando quieras.")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .padding(.horizontal, 30)

                periodCard
                    .padding(.top, 24)
                    .padding(.horizontal, 20)

                buttons
                    .padding(.top, 26)
                    .padding(.bottom, 36)
            }
        }
        .background(palette.background)
    }

    // MARK: - El rango

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DESDE")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.tertiaryLabel)

            HStack(spacing: 8) {
                ForEach(Self.standardPeriods, id: \.self) { months in
                    chip(label: chipLabel(months),
                         isActive: !showsCustom && readPeriodMonths == months) {
                        showsCustom = false
                        readPeriodMonths = months
                    }
                }
                chip(label: "Otro", isActive: showsCustom) { showsCustom = true }
            }

            if showsCustom {
                HStack {
                    Text("Cuánto atrás")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    Spacer()
                    HStack(spacing: 0) {
                        stepper("minus") { readPeriodMonths = min(36, readPeriodMonths + 1) }
                        Text("\(readPeriodMonths)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.label)
                            .frame(minWidth: 28)
                        stepper("plus") { readPeriodMonths = max(1, readPeriodMonths - 1) }
                    }
                    .padding(.horizontal, 4)
                    .background(palette.track)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

            Text(rangeLabel)
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.tertiaryLabel)
                Text(readPeriodMonths >= 12
                     ? "Un año tarda un poco más; puedes seguir usando la app mientras lee."
                     : "Tarda unos segundos. Puedes ampliarlo después en Ajustes → Gmail y bancos.")
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
            }
        }
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.hairline, lineWidth: 0.5)
        )
    }

    /// Abreviado igual que en Gmail y bancos: cinco opciones tienen que caber
    /// en una fila. El botón de abajo dice el periodo completo.
    private func chipLabel(_ months: Int) -> String {
        if months > 0, months % 12 == 0 { return "\(months / 12) A" }
        return "\(months) M"
    }

    private func periodLabel(_ months: Int) -> String {
        if months == 12 { return "1 año" }
        if months > 0, months % 12 == 0 { return "\(months / 12) años" }
        return months == 1 ? "1 mes" : "\(months) meses"
    }

    private var rangeStartDate: Date {
        Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .month, value: -readPeriodMonths, to: Date()) ?? Date())
    }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PE")
        f.dateFormat = "d MMM yyyy"
        return "Desde el \(f.string(from: rangeStartDate)) hasta hoy."
    }

    private func chip(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? .white : palette.label)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isActive ? accent.color : palette.track)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stepper(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(palette.label)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Acciones

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                startReading()
            } label: {
                HStack(spacing: 8) {
                    if isStarting { ProgressView().tint(.white) }
                    Text("Leer " + periodLabel(readPeriodMonths))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(accent.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isStarting)

            Button("No leer mis correos · empezar de cero") { onDone(nil) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(palette.secondaryLabel)
                .disabled(isStarting)
        }
        .padding(.horizontal, 24)
    }

    /// Se lanza la lectura y se entra a la app sin esperarla: el progreso ya se
    /// ve en el Resumen, y quedarse en una pantalla de carga durante un año de
    /// correo sería la peor primera impresión posible.
    /// Lanza la lectura y cede el paso a la pantalla de progreso. Entrar a la
    /// app aquí era el error: SwiftData sigue insertando gastos y el Resumen se
    /// siente trabado — la app no va lenta, se entraba demasiado pronto.
    private func startReading() {
        isStarting = true
        GmailSyncService.shared.modelContext = modelContext
        GmailSyncService.shared.syncEmails(force: true, startDate: rangeStartDate, endDate: Date())
        onDone(periodLabel(readPeriodMonths))
    }
}
