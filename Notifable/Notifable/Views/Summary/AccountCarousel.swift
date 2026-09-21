import SwiftUI
import SwiftData

/// El logo de una cuenta: el de su banco o billetera si hay asset, y si no un
/// símbolo (efectivo, una tarjeta sin banco, una persona).
struct AccountLogo: View {
    let institution: Institution?
    var size: CGFloat = 26

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        if let asset = institution?.logoAsset {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .background(Color.white)
                .clipShape(Circle())
        } else {
            Image(systemName: institution?.symbol ?? "person.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(palette.secondaryLabel)
                .frame(width: size, height: size)
                .background(palette.track, in: Circle())
        }
    }
}

/// Cómo se llama y cómo se dibuja una cuenta del catálogo, ya con el nombre
/// que le diste en «Tus cuentas».
struct AccountBadge: Equatable {
    let name: String
    let institution: Institution?
}

// MARK: - Carrusel (`1b`)

/// Resumen › Movimientos: las cuentas tuyas como tarjetas, para filtrar la
/// lista por una. «Todas» va primero y «Editar» queda fijo al borde derecho,
/// siempre a mano aunque haya diez cuentas.
struct AccountCarousel: View {
    let accounts: [DetectedAccount]
    let name: (DetectedAccount) -> String
    /// Movimientos de la lista actual (Gastos, Ingresos o Por cobrar) por
    /// cuenta. Una cuenta sin ninguno sigue ahí: el carrusel no salta al
    /// cambiar de pestaña.
    let counts: [String: Int]
    let total: Int
    @Binding var selection: String?
    let onEdit: () -> Void

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    private static let cardWidth: CGFloat = 110
    private static let editWidth: CGFloat = 52

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                card(selected: selection == nil, label: "Todas las cuentas") {
                    selection = nil
                } content: { isOn in
                    allStack(isOn: isOn)
                    title("Todas", isOn: isOn)
                    line("\(total) mov.", isOn: isOn)
                }

                ForEach(accounts) { account in
                    let isOn = selection == account.key
                    card(selected: isOn, label: name(account)) {
                        selection = isOn ? nil : account.key
                    } content: { isOn in
                        AccountLogo(institution: account.institution ?? account.via)
                        title(name(account), isOn: isOn)
                        line(detail(account), isOn: isOn)
                    }
                }
            }
            // Todas las tarjetas del alto de la más alta.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
            .padding(.trailing, 16 + Self.editWidth + 14)
        }
        .overlay(alignment: .trailing) { editTile }
    }

    private func detail(_ account: DetectedAccount) -> String {
        let count = counts[account.key] ?? 0
        if let digits = account.digits { return "•••• \(digits) · \(count)" }
        return "\(count) mov."
    }

    // MARK: Piezas

    private func card<Content: View>(selected: Bool,
                                     label: String,
                                     action: @escaping () -> Void,
                                     @ViewBuilder content: @escaping (Bool) -> Content) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                content(selected)
            }
            .frame(width: Self.cardWidth - 24, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(selected ? accent.softFill(scheme) : palette.surface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? accent.color : palette.hairline, lineWidth: selected ? 1.5 : 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Dos cuadrados montados: «todas las cuentas» sin elegir el logo de una.
    private func allStack(isOn: Bool) -> some View {
        let ink = isOn ? accent.color : palette.label
        return HStack(spacing: -9) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ink.opacity(isOn ? 0.30 : 0.10))
                .frame(width: 26, height: 26)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ink.opacity(isOn ? 0.16 : 0.06))
                .frame(width: 26, height: 26)
        }
    }

    private func title(_ text: String, isOn: Bool) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? accent.onSurface(scheme) : palette.label)
            .lineLimit(1)
    }

    private func line(_ text: String, isOn: Bool) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(isOn ? accent.onSurface(scheme) : palette.secondaryLabel)
            .lineLimit(1)
    }

    /// Fijo al borde, sobre un degradado que funde las tarjetas que pasan por
    /// debajo.
    private var editTile: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [palette.background.opacity(0), palette.background],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 30)

            Button(action: onEdit) {
                Text("Editar")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(accent.onSurface(scheme))
                    .frame(width: Self.editWidth)
                    .frame(maxHeight: .infinity)
                    .background(palette.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(palette.secondaryLabel.opacity(0.45),
                                          style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Editar tus cuentas")
            .padding(.trailing, 16)
            .background(palette.background)
        }
    }
}

// MARK: - Traslados

/// Un traslado ya resuelto para dibujar: de qué cuenta a cuál. Si el gasto y
/// el ingreso del mismo movimiento llegaron los dos (Plin de BBVA → Yape
/// recibido), es **una** fila; si sólo llegó una mitad, la otra se nombra con
/// lo que se sepa (la billetera de destino o el nombre del destinatario).
struct TransferEntry: Identifiable {
    let id: UUID
    let from: AccountBadge
    let to: AccountBadge
    let amount: Double
    let currency: String
    let date: Date
    let expense: Expense?
    let income: Income?

    /// Toca alguna de estas cuentas (para el filtro del carrusel).
    let keys: Set<String>
}

struct TransferRowView: View {
    let entry: TransferEntry
    var onTap: () -> Void = {}

    @Environment(\.colorScheme) private var scheme
    private var palette: Palette { Palette(scheme) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                AccountLogo(institution: entry.from.institution, size: 30)
                    .overlay(Circle().stroke(palette.surface, lineWidth: 1.5))
                AccountLogo(institution: entry.to.institution, size: 30)
                    .overlay(Circle().stroke(palette.surface, lineWidth: 1.5))
                    .offset(x: 14, y: 12)
            }
            .frame(width: 44, height: 44, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.from.name + " → " + entry.to.name)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(palette.label)
                    .lineLimit(1)

                Text(TodayView.dayLabel(for: entry.date) + " · entre tus cuentas")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Sin signo: no entra ni sale nada de lo tuyo.
            Text(Money.format(entry.amount, currency: entry.currency))
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(palette.secondaryLabel)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tus cuentas (`1c`)

/// «Editar» del carrusel: las cuentas detectadas en tus movimientos, cuáles
/// son tuyas, cómo se llaman y en qué orden van.
///
/// Todo lo que esté aquí marcado es tuyo, y lo que se mueva **hacia** una
/// cuenta tuya es traslado: no cuenta como gasto (ni como ingreso del otro
/// lado). No hay «agrupar»: la app no lleva saldos, sólo evita contar dos
/// veces el mismo dinero.
///
/// Los cambios son un borrador hasta «Listo»; «Cancelar» no toca nada.
struct AccountsSheet: View {
    let catalog: AccountCatalog

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @State private var draft: AccountPreferences
    @State private var query = ""

    private var palette: Palette { Palette(scheme) }
    private var accent: AppThemeColor { .current }

    init(catalog: AccountCatalog, preferences: AccountPreferences) {
        self.catalog = catalog
        _draft = State(initialValue: preferences)
    }

    // MARK: Datos

    private func matches(_ account: DetectedAccount) -> Bool {
        let needle = AccountResolver.folded(query)
        guard !needle.isEmpty else { return true }
        return AccountResolver.folded(draft.name(for: account)).contains(needle)
            || AccountResolver.folded(account.detectedName).contains(needle)
            || (account.digits?.contains(needle) ?? false)
    }

    private var mine: [DetectedAccount] {
        draft.carousel(from: catalog).filter(matches)
    }

    /// Primero tus tarjetas apagadas, luego los destinatarios por cuántas
    /// veces les enviaste: el tuyo suele estar entre los primeros.
    private var others: [DetectedAccount] {
        catalog.accounts.values
            .filter { !draft.isMine($0.key) && matches($0) }
            .sorted { a, b in
                if a.isOrigin != b.isOrigin { return a.isOrigin }
                if a.count != b.count { return a.count > b.count }
                return a.detectedName < b.detectedName
            }
    }

    // MARK: Vista

    var body: some View {
        let mine = self.mine
        let others = self.others

        NavigationStack {
            List {
                Section {
                    Text("Marca las cuentas que son tuyas. Lo que se mueva hacia ellas se registra como traslado y no cuenta como gasto.")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.secondaryLabel)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 0, trailing: 6))
                }

                if !mine.isEmpty {
                    Section {
                        ForEach(mine) { account in
                            row(account, isMine: true)
                        }
                        .onMove(perform: query.isEmpty ? move : nil)
                    } header: {
                        header("En tu carrusel", count: mine.count)
                    } footer: {
                        Text("Mantén pulsado para cambiar el orden. Toca el nombre para renombrarla.")
                    }
                }

                if !others.isEmpty {
                    Section {
                        ForEach(others) { account in
                            row(account, isMine: false)
                        }
                    } header: {
                        header("Otras detectadas", count: others.count)
                    } footer: {
                        Text("Si un destinatario eres tú —tu Plin, tu otra cuenta—, márcalo: lo que le envíes dejará de contar como gasto, y lo que te llegue de él, como ingreso.")
                    }
                }

                if mine.isEmpty && others.isEmpty {
                    Section {
                        VStack(spacing: 6) {
                            Text(query.isEmpty ? "Aún no hay cuentas" : "Sin coincidencias")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(palette.label)
                            Text("Las cuentas aparecen aquí cuando la app lee un aviso de ese banco o billetera.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(palette.secondaryLabel)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            // Sin el margen de arriba de la lista, el texto queda pegado al
            // buscador en vez de a una pantalla de distancia.
            .contentMargins(.top, 0, for: .scrollContent)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Busca entre las cuentas detectadas")
            .navigationTitle("Tus cuentas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(accent.onSurface(scheme))
    }

    private func header(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
        }
    }

    private func row(_ account: DetectedAccount, isMine: Bool) -> some View {
        HStack(spacing: 10) {
            if isMine {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.tertiaryLabel)
                    .frame(width: 14)
            }

            AccountLogo(institution: account.institution ?? account.via, size: 34)

            VStack(alignment: .leading, spacing: 1) {
                if isMine {
                    TextField(account.detectedName, text: nameBinding(account))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.label)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                } else {
                    Text(draft.name(for: account))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.label)
                        .lineLimit(1)
                }

                Text(meta(account))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: mineBinding(account))
                .labelsHidden()
                .tint(accent.color)
                .accessibilityLabel(draft.name(for: account) + ", es tuya")
        }
        .padding(.vertical, 2)
    }

    private func meta(_ account: DetectedAccount) -> String {
        let count = account.count == 1 ? "1 movimiento" : "\(account.count) movimientos"
        let renamed = draft.names[account.key].map { !$0.isEmpty } ?? false
        var parts: [String] = []
        if account.isOrigin {
            if let digits = account.digits { parts.append("•••• " + digits) }
            if account.institution == .efectivo { parts.append("Anotados a mano") }
            if renamed { parts.insert(account.detectedName, at: 0) }
        } else {
            if renamed { parts.append(account.detectedName) }
            if let phone = account.phone { parts.append("Cel. •" + phone) }
            switch account.via {
            case .yape?: parts.append("Por Yape")
            case .plin?: parts.append("Por Plin")
            case .bbva?: parts.append("Transferencia BBVA")
            case .some(let other): parts.append("Por " + other.name)
            case nil:    parts.append("Te envía dinero")
            }
        }
        parts.append(count)
        return parts.joined(separator: " · ")
    }

    // MARK: Borrador

    private func nameBinding(_ account: DetectedAccount) -> Binding<String> {
        Binding {
            draft.name(for: account)
        } set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            var unnamed = draft
            unnamed.names[account.key] = nil
            draft.names[account.key] = trimmed.isEmpty || trimmed == unnamed.name(for: account) ? nil : value
        }
    }

    private func mineBinding(_ account: DetectedAccount) -> Binding<Bool> {
        Binding {
            draft.isMine(account.key)
        } set: { isOn in
            withAnimation(.easeInOut(duration: 0.22)) {
                // Sólo se guarda lo que difiere del valor por defecto.
                draft.mine[account.key] = isOn == AccountResolver.isOrigin(account.key) ? nil : isOn
                draft.order.removeAll { $0 == account.key }
                if isOn { draft.order = draft.carousel(from: catalog).map(\.key).filter { $0 != account.key } + [account.key] }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var keys = draft.carousel(from: catalog).map(\.key)
        keys.move(fromOffsets: source, toOffset: destination)
        draft.order = keys
    }

    private func save() {
        AccountBook.shared.replace(with: draft)
        TransferDetector.apply(in: modelContext, preferences: draft)
        dismiss()
    }
}
