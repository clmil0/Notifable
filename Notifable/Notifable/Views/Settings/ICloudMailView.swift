import SwiftUI
import SwiftData

/// Conectar un buzón de iCloud.
///
/// La pantalla tiene que explicar algo incómodo y no esconderlo: aquí **sí** se
/// teclea una contraseña, al revés que en Gmail. No es un capricho del diseño
/// —Apple no publica ninguna API de correo para iCloud, así que no hay OAuth ni
/// permiso de sólo lectura que pedir—, pero el usuario merece saber qué está
/// entregando y cómo quitarlo. Ver `ICloudMailAccount`.
struct ICloudMailView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @StateObject private var sync = ICloudSyncService.shared
    @AppStorage("appAccentColor") private var appAccentColor = AppThemeColor.blue.rawValue

    @State private var address = ICloudMailAccount.address ?? ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @State private var isConnected = ICloudMailAccount.isConnected
    @State private var showDisconnectDialog = false
    @State private var months = 1

    private var tint: Color { (AppThemeColor(rawValue: appAccentColor) ?? .purple).color }

    var body: some View {
        Form {
            if isConnected {
                connectedSection
                readSection
                disconnectSection
            } else {
                explanationSection
                formSection
            }

            if let error {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("iCloud Mail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sync.modelContext = modelContext }
        .confirmationDialog("¿Desconectar iCloud?",
                            isPresented: $showDisconnectDialog,
                            titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { disconnect() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los movimientos ya registrados se conservan. Dejarán de entrar nuevos desde este buzón.")
        }
    }

    // MARK: - Sin conectar

    private var explanationSection: some View {
        Section {
            Label("Apple no ofrece el permiso de sólo lectura que sí da Gmail",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("""
            Con Gmail apruebas en Google y AgruPay recibe un permiso limitado a leer, \
            sin ver nunca tu contraseña. Para iCloud, Apple sólo permite conectarse con una \
            **contraseña específica de aplicación**, que abre el buzón entero.

            AgruPay se limita sola: abre el correo en modo sólo lectura y ni siquiera lo marca \
            como leído. Pero es una limitación nuestra, no un permiso que Apple imponga.

            Puedes retirarla cuando quieras desde appleid.apple.com, sin tocar tu contraseña \
            de Apple.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Antes de empezar")
        }
    }

    private var formSection: some View {
        Section {
            steps

            TextField("tucorreo@icloud.com", text: $address)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("Contraseña específica (16 letras)", text: $password)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if isWorking { ProgressView().padding(.trailing, 6) }
                    Text(isWorking ? "Comprobando…" : "Conectar")
                }
            }
            .disabled(isWorking || address.isEmpty || password.isEmpty)
        } header: {
            Text("Conectar")
        } footer: {
            if !password.isEmpty, !ICloudMailAccount.looksLikeAppPassword(password) {
                // Aviso, no bloqueo: si Apple cambiara el formato, rechazar por
                // la forma dejaría la pantalla inservible.
                Text("Una contraseña específica son 16 letras, normalmente en cuatro grupos. ¿Seguro que no pusiste la de tu Apple ID?")
                    .foregroundStyle(.orange)
            } else {
                Text("Se guarda en el Keychain de este iPhone, sólo accesible con el teléfono desbloqueado, y no viaja al respaldo de iCloud.")
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepRow(1, "Entra en appleid.apple.com y firma con tu Apple ID.")
            stepRow(2, "Ve a «Inicio de sesión y seguridad» → «Contraseñas específicas para apps».")
            stepRow(3, "Genera una nueva y llámala «AgruPay».")
            stepRow(4, "Cópiala aquí abajo junto con tu dirección de iCloud.")

            Link(destination: URL(string: "https://appleid.apple.com")!) {
                Label("Abrir appleid.apple.com", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .frame(width: 20, height: 20)
                .background(tint.opacity(0.15), in: Circle())
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Conectado

    private var connectedSection: some View {
        Section {
            LabeledContent("Cuenta", value: ICloudMailAccount.address ?? "—")
            LabeledContent("Última lectura",
                           value: ICloudMailAccount.lastSync.map(Self.relative) ?? "Nunca")
        } header: {
            Text("Conectada")
        } footer: {
            Text("AgruPay sólo abre los correos de los bancos que tengas activos, en modo lectura, y no los marca como leídos.")
        }
    }

    private var readSection: some View {
        Section {
            Picker("Leer desde", selection: $months) {
                Text("Último mes").tag(1)
                Text("Últimos 3 meses").tag(3)
                Text("Últimos 6 meses").tag(6)
                Text("Último año").tag(12)
            }

            Button {
                Task { await runSync() }
            } label: {
                HStack {
                    if sync.isSyncing { ProgressView().padding(.trailing, 6) }
                    Text(sync.isSyncing ? "Leyendo…" : "Leer ahora")
                }
            }
            .disabled(sync.isSyncing)

            if sync.isSyncing, sync.totalToProcess > 0 {
                ProgressView(value: Double(sync.processed), total: Double(sync.totalToProcess)) {
                    Text("\(sync.processed) de \(sync.totalToProcess) correos")
                        .font(.caption)
                }
            }

            let found = sync.foundByBank.filter { $0.value > 0 }.sorted { $0.key < $1.key }
            if !found.isEmpty {
                ForEach(found, id: \.key) { bank, count in
                    LabeledContent(bank, value: count == 1 ? "1 movimiento" : "\(count) movimientos")
                        .font(.footnote)
                }
            }

            if let syncError = sync.lastError {
                Text(syncError)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Leer correo")
        }
    }

    private var disconnectSection: some View {
        Section {
            Button("Desconectar iCloud", role: .destructive) { showDisconnectDialog = true }
        } footer: {
            Text("Recuerda retirar además la contraseña específica en appleid.apple.com: es lo único que la deja de verdad sin efecto.")
        }
    }

    // MARK: - Acciones

    /// Se comprueba **antes** de guardar: decir "conectada" y que falle en la
    /// primera lectura deja al usuario sin saber si se equivocó de contraseña o
    /// si simplemente no había correos.
    private func connect() async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        if let failure = await sync.verify(address: address, password: password) {
            error = failure
            return
        }
        do {
            try ICloudMailAccount.save(address: address, password: password)
            password = ""
            isConnected = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runSync() async {
        sync.modelContext = modelContext
        let start = Calendar.current.date(byAdding: .month, value: -months, to: Date())
        await sync.sync(startDate: start)
    }

    private func disconnect() {
        ICloudMailAccount.disconnect()
        ICloudSyncService.resetSyncState()
        address = ""
        password = ""
        isConnected = false
        error = nil
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es_PE")
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
