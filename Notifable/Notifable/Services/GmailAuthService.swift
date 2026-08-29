import Foundation
import AuthenticationServices
import CryptoKit

class GmailAuthService: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    static let shared = GmailAuthService()
    
    @Published var isAuthenticated: Bool = false
    
    private let clientID = "565627106864-cd3nnm389bdf9cfdqo015d7tbm052bdr.apps.googleusercontent.com"
    private let redirectURI = "com.googleusercontent.apps.565627106864-cd3nnm389bdf9cfdqo015d7tbm052bdr:/oauth2callback"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let scope = "https://www.googleapis.com/auth/gmail.readonly"
    
    private var authSession: ASWebAuthenticationSession?
    
    override init() {
        super.init()
        checkAuthStatus()
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first ?? ASPresentationAnchor()
    }
    
    func checkAuthStatus() {
        isAuthenticated = getAccessToken() != nil || getRefreshToken() != nil
    }
    
    func signIn() {
        guard let url = URL(string: "\(authURL)?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scope)&prompt=consent&access_type=offline") else { return }
        
        let scheme = "com.googleusercontent.apps.565627106864-cd3nnm389bdf9cfdqo015d7tbm052bdr"
        
        authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
            guard error == nil, let callbackURL = callbackURL else {
                print("Auth Error: \(String(describing: error))")
                return
            }
            
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                print("No code found in callback URL")
                return
            }
            
            self.exchangeCodeForToken(code: code)
        }
        
        authSession?.presentationContextProvider = self
        authSession?.start()
    }
    
    func signOut() {
        UserDefaults.standard.removeObject(forKey: "GmailAccessToken")
        UserDefaults.standard.removeObject(forKey: "GmailRefreshToken")
        DispatchQueue.main.async {
            self.isAuthenticated = false
        }
    }
    
    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: tokenURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "code=\(code)&client_id=\(clientID)&redirect_uri=\(redirectURI)&grant_type=authorization_code"
        request.httpBody = bodyString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    if let accessToken = json["access_token"] as? String {
                        self.saveAccessToken(accessToken)
                    }
                    if let refreshToken = json["refresh_token"] as? String {
                        self.saveRefreshToken(refreshToken)
                    }
                    DispatchQueue.main.async {
                        self.checkAuthStatus()
                    }
                }
            } catch {
                print("Failed to parse token response: \(error)")
            }
        }.resume()
    }
    
    func refreshAccessToken(completion: @escaping (String?) -> Void) {
        guard let refreshToken = getRefreshToken(), let url = URL(string: tokenURL) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyString = "client_id=\(clientID)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = bodyString.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let newAccessToken = json["access_token"] as? String {
                    self.saveAccessToken(newAccessToken)
                    completion(newAccessToken)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    // For simplicity, using UserDefaults, but Keychain is recommended for production
    private func saveAccessToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "GmailAccessToken")
    }
    
    func getAccessToken() -> String? {
        return UserDefaults.standard.string(forKey: "GmailAccessToken")
    }
    
    private func saveRefreshToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: "GmailRefreshToken")
    }
    
    private func getRefreshToken() -> String? {
        return UserDefaults.standard.string(forKey: "GmailRefreshToken")
    }
}

class WindowPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: UIWindow
    init(window: UIWindow) {
        self.window = window
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window
    }
}
