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
        // 从 Keychain 读取登录态
        isLoggedIn = APIClient.shared.token != nil
        // 401 会话失效：自动切回登录页
        NotificationCenter.default.addObserver(
            forName: APIClient.sessionExpiredNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.isLoggedIn = false
        }
    }
}