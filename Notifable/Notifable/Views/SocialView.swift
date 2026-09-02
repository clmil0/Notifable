import SwiftUI

// MARK: - Sync Manager (Supabase REST API)
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
                DispatchQueue.main.async {
                    self.socialFeed = expenses
                }
            } else {
                print("Error fetching from Supabase. Did you create the table?")
            }
        } catch {
            print("Network error: \(error)")
        }
    }
    
    func syncLocalExpensesToCloud(localExpenses: [Expense]) async {
        guard !localExpenses.isEmpty else { return }
        DispatchQueue.main.async { self.isSyncing = true }
        defer { DispatchQueue.main.async { self.isSyncing = false } }
        
        guard let url = URL(string: "\(projectURL)/rest/v1/expenses") else { return }
        
        // Convert local models to JSON for Supabase
        let payloads = localExpenses.map { exp -> [String: Any] in
            return [
                "id": exp.id.uuidString,
                "user_id": "Usuario_PoC", // Dummy user ID for now
                "amount": exp.amount,
                "merchant": exp.merchant,
                "category": exp.category
            ]
        }
        
        guard let body = try? JSONSerialization.data(withJSONObject: payloads) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Upsert to avoid duplicate key errors if already synced
        request.addValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.addValue("id", forHTTPHeaderField: "on_conflict") 
        
        request.httpBody = body
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                print("Sync exitoso a Supabase")
            } else {
                print("Error en el Sync. Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            print("Network error during sync: \(error)")
        }
    }
}

// MARK: - Social View
struct SocialView: View {
    @State private var syncManager = SyncManager.shared
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        ZStack {
            if syncManager.socialFeed.isEmpty {
                ContentUnavailableView(
                    "Sin Datos de Amigos",
                    systemImage: "person.3.fill",
                    description: Text("No se encontraron transacciones en Supabase. ¿Ya creaste la tabla 'expenses'?")
                )
            } else {
                TrackableScrollView(scrollOffset: $scrollOffset) {
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
    SocialView(scrollOffset: .constant(100))
}
