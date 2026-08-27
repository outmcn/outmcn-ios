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
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
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
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)

                    VStack(spacing: 6) {
                        Text("OutMCN Tools v1.5.1").font(.system(size: 13, weight: .semibold))
                        Text("数据与 outmcn.net 实时同步")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
                }
                .padding(16)
            }
        }
        .confirmationDialog("确定退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await APIClient.shared.logout(); session.isLoggedIn = false }
            }
            Button("取消", role: .cancel) {}
        }
    }
}