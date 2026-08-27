import SwiftUI

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
    }
}

struct SettingsTabView: View {
    @EnvironmentObject var session: SessionStore
    @State private var confirmLogout = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("账号")) {
                    HStack {
                        Text("账号")
                        Spacer()
                        Text(session.username).foregroundColor(.secondary)
                    }
                    Button("退出登录", role: .destructive) {
                        confirmLogout = true
                    }
                }
                Section(footer: Text("OutMCN Tools v1.4.1")) {
                    Text("数据与 outmcn.net 实时同步")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("确定退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    Task { await APIClient.shared.logout(); session.isLoggedIn = false }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}