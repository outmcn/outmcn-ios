import SwiftUI

@main
struct OutMCNApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            if session.isLoggedIn {
                MainTabView()
                    .environmentObject(session)
            } else {
                LoginView()
                    .environmentObject(session)
            }
        }
    }
}

/// 会话状态
class SessionStore: ObservableObject {
    @Published var isLoggedIn: Bool {
        didSet {
            if !isLoggedIn { APIClient.shared.token = nil }
        }
    }
    @Published var username: String = "admin"

    init() {
        isLoggedIn = APIClient.shared.token != nil
    }
}