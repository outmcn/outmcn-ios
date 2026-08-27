import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var loading = false
    @State private var errorMsg: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.49, green: 0.36, blue: 1.0),
                                    Color(red: 0.36, green: 0.55, blue: 1.0),
                                    Color(red: 0.13, green: 0.79, blue: 0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                // Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.white)
                }
                .padding(.bottom, 8)

                Text("OutMCN")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundColor(.white)

                Text("网关 · 模型 · 设置")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))

                // 登录表单卡片
                VStack(spacing: 14) {
                    TextField("账号", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                    SecureField("密码", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit { doLogin() }

                    if let e = errorMsg {
                        Text(e)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    Button(action: doLogin) {
                        Group {
                            if loading {
                                ProgressView().tint(.white)
                            } else {
                                Text("进入系统").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .background(Color.white.opacity(0.22))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(loading)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.15)))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.25)))
                .padding(.horizontal, 28)
            }
        }
    }

    private func doLogin() {
        guard !username.isEmpty, !password.isEmpty else {
            errorMsg = "请输入账号和密码"; return
        }
        errorMsg = nil
        loading = true
        Task {
            do {
                _ = try await APIClient.shared.login(user: username, pass: password)
                DispatchQueue.main.async {
                    session.username = username
                    session.isLoggedIn = true
                    loading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMsg = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}