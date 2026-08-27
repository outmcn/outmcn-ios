import SwiftUI
import UIKit

// ---------- 双击底部 tab 刷新 ----------
extension Notification.Name {
    static let outmcnRefreshGateways = Notification.Name("outmcn.refresh.gateways")
    static let outmcnRefreshModels = Notification.Name("outmcn.refresh.models")
    static let outmcnRefreshSettings = Notification.Name("outmcn.refresh.settings")
}

/// 检测 UITabBar 双击（同一 tab 500ms 内第二次点击）
struct TabBarDoubleTapDetector: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            install(in: vc, coordinator: context.coordinator)
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private func install(in vc: UIViewController, coordinator: Coordinator) {
        guard let tbc = findTabBarController(from: vc.view.window) else { return }
        tbc.delegate = coordinator
    }
    private func findTabBarController(from window: UIWindow?) -> UITabBarController? {
        guard let root = window?.rootViewController else { return nil }
        var cur: UIViewController? = root
        var depth = 0
        while let v = cur, depth < 6 {
            if let t = v as? UITabBarController { return t }
            if let nav = v as? UINavigationController {
                cur = nav.visibleViewController ?? nav.topViewController
            } else {
                cur = v.presentedViewController ?? v.children.first
            }
            depth += 1
        }
        return nil
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        private var lastIndex = -1
        private var lastTime: TimeInterval = 0

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let idx = tabBarController.selectedIndex
            let now = Date().timeIntervalSince1970
            if idx == lastIndex && (now - lastTime) < 0.5 {
                switch idx {
                case 0: NotificationCenter.default.post(name: .outmcnRefreshGateways, object: nil)
                case 1: NotificationCenter.default.post(name: .outmcnRefreshModels, object: nil)
                case 2: NotificationCenter.default.post(name: .outmcnRefreshSettings, object: nil)
                default: break
                }
            }
            lastIndex = idx
            lastTime = now
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var session: SessionStore

    var body: some View {
        TabView {
            GatewaysTabView()
                .tabItem { Label("网关", systemImage: "server.rack") }
            ModelsTabView()
                .tabItem { Label("模型", systemImage: "cpu") }
            SettingsTabView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .background(TabBarDoubleTapDetector())
    }
}

struct SettingsTabView: View {
    @EnvironmentObject var session: SessionStore
    @State private var confirmLogout = false
    @State private var showAddModel = false
    @State private var chatRunning = false
    @State private var chatBusy = false
    @State private var chatLoaded = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                // 顶部居中标题
                HStack {
                    Spacer()
                    Text("设置")
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScrollView {
                    VStack(spacing: 14) {
                        // hermes 网页会话开关
                        VStack(spacing: 10) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)
                                Text("网页会话").font(.system(size: 15))
                                Spacer()
                                Circle()
                                    .fill(chatRunning ? Color.green : Color.red)
                                    .frame(width: 9, height: 9)
                            }
                            Divider()
                            Button {
                                toggleChat()
                            } label: {
                                Group {
                                    if chatBusy {
                                        ProgressView().frame(maxWidth: .infinity)
                                    } else {
                                        Text(chatRunning ? "关闭" : "开始")
                                            .font(.system(size: 15, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(chatBusy)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))

                        // 添加模型入口
                        Button {
                            showAddModel = true
                        } label: {
                            HStack {
                                Image(systemName: "cpu")
                                    .font(.system(size: 16))
                                    .foregroundColor(.accentColor)
                                Text("添加模型")
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(16)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                        }
                        .sheet(isPresented: $showAddModel) {
                            ModelFormView(model: nil, isDuplicate: false) { _ in
                                showAddModel = false
                            }
                        }

                        // 账号卡片
                        VStack(spacing: 10) {
                            HStack {
                                Text("账号").font(.system(size: 15))
                                Spacer()
                                Text(session.username).foregroundColor(.secondary).font(.system(size: 15))
                            }
                            Divider()
                            Button {
                                confirmLogout = true
                            } label: {
                                HStack {
                                    Text("退出登录").font(.system(size: 15)).foregroundColor(.red)
                                    Spacer()
                                }
                            }
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
                    }
                    .padding(16)
                }
            }
        }
        .confirmationDialog("确定退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await APIClient.shared.logout(); session.isLoggedIn = false }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear { loadChatState() }
        .onReceive(NotificationCenter.default.publisher(for: .outmcnRefreshSettings)) { _ in
            loadChatState()
        }
    }

    private func loadChatState() {
        Task {
            do {
                let running = try await APIClient.shared.dashboardStatus()
                DispatchQueue.main.async {
                    chatRunning = running
                    chatLoaded = true
                }
            } catch {
                // 静默失败，保持上次状态
            }
        }
    }

    private func toggleChat() {
        chatBusy = true
        let action = chatRunning ? "stop" : "start"
        Task {
            do {
                let r = try await APIClient.shared.dashboardAction(action)
                DispatchQueue.main.async {
                    chatBusy = false
                    chatRunning = r.running
                }
            } catch {
                DispatchQueue.main.async {
                    chatBusy = false
                }
            }
        }
    }
}