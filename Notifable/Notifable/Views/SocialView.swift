import SwiftUI

// MARK: - Sync Manager (Supabase REST API)
/// `@MainActor`: sólo lo usa `SocialView`, y su estado (`socialFeed`,
/// `isSyncing`) se lee desde la vista. Aislarlo al actor principal quita el
/// aviso de capturar un tipo no-Sendable en un cierre `@Sendable` sin tener
/// que envolver cada asignación.
@MainActor
@Observable
class SyncManager {
    static let shared = SyncManager()
    
    // Supabase Credentials
    private let projectURL = "https://zjzzqaeusmxmtszgdncl.supabase.co"
    private let apiKey = "sb_publishable_NVM2GcvxZFmf0VLNbaBr7A_y_8EMS97"
    
    var socialFeed: [SocialExpense] = []
    var isSyncing = false
    
    struct SocialExpense: Codable, Identifiable {
        let id: String
        let user_id: String
        let amount: Double
        let merchant: String
        let category: String
        let created_at: String
    }
    
    func fetchSocialFeed() async {
        guard let url = URL(string: "\(projectURL)/rest/v1/expenses?select=*&order=created_at.desc&limit=20") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                let expenses = try decoder.decode([SocialExpense].self, from: data)
                self.socialFeed = expenses
            } else {
                print("Error fetching from Supabase. Did you create the table?")
            }
        } catch {
            print("Network error: \(error)")
        }
    }
    
    // `syncLocalExpensesToCloud` se eliminó: subía TODOS los gastos del usuario
    // a la tabla pública `expenses` con el user_id fijo "Usuario_PoC", cada 30
    // minutos y sin que nadie lo pidiera. Lo único que sube ahora a la nube es
    // la configuración (ver ConfigBackupManager); los gastos se quedan en el
    // teléfono y se rearman releyendo el correo.

}

// MARK: - Social View
struct SocialView: View {
    @State private var syncManager = SyncManager.shared
    
    var body: some View {
        ZStack {
            if syncManager.socialFeed.isEmpty {
                ContentUnavailableView(
                    "Sin Datos de Amigos",
                    systemImage: "person.3.fill",
                    description: Text("No se encontraron transacciones en Supabase. ¿Ya creaste la tabla 'expenses'?")
                )
            } else {
                TrackableScrollView {
                    VStack(spacing: 16) {
                        ForEach(syncManager.socialFeed) { expense in
                            HStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                    .overlay(Text(expense.user_id.prefix(1)).font(.headline).foregroundStyle(.orange))
                                
                                VStack(alignment: .leading) {
                                    Text("\(expense.user_id) gastó en \(expense.merchant)")
                                        .font(.subheadline)
                                    Text(expense.category)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                
                                Spacer()
                                
                                Text("$\(expense.amount, specifier: "%.2f")")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            .surfaceCard(radius: 16)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .task {
            await syncManager.fetchSocialFeed()
        }
    }
}

#Preview {
    SocialView()
}
