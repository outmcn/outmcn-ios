import Foundation

/// OutMCN API 客户端：x-token 认证（同网页端）
class APIClient {
    static let shared = APIClient()
    let baseURL = "https://outmcn.net"

    private let tokenKey = "outmcn_token"
    var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: tokenKey) }
            else { UserDefaults.standard.removeObject(forKey: tokenKey) }
            UserDefaults.standard.synchronize()
        }
    }

    func login(user: String, pass: String) async throws -> String {
        var req = URLRequest(url: URL(string: baseURL + "/api/login")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["user": user, "pass": pass])
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.network }
        let d = try JSONDecoder().decode(LoginResponse.self, from: data)
        guard http.statusCode == 200, let t = d.token else {
            throw APIError.message(d.error ?? "登录失败（HTTP \(http.statusCode)）")
        }
        token = t
        return t
    }

    func logout() async {
        _ = try? await request("/api/logout", body: [:], method: "POST") as Empty
        token = nil
    }

    // ---------- 网关设置 ----------
    func fetchGateways() async throws -> (gateways: [GatewayInfo], models: [ModelInfo]) {
        let d: HMResponse = try await request("/api/hm/gateways")
        return (d.gateways ?? [], d.models ?? [])
    }
    func gatewayService(_ service: String, action: String) async throws -> String {
        let d: HMResponse = try await request("/api/hm/service", body: ["service": service, "action": action], method: "POST")
        return d.message ?? d.error ?? "OK"
    }
    func applyModel(gateway: String, modelID: String) async throws -> String {
        let d: HMResponse = try await request("/api/hm/apply", body: ["gateway": gateway, "model_id": modelID], method: "POST")
        return d.message ?? d.error ?? "OK"
    }
    func fetchModels() async throws -> [ModelInfo] {
        let d: HMResponse = try await request("/api/hm/models")
        return d.models ?? []
    }
    func createModel(_ m: ModelInfo) async throws -> String {
        let d: HMResponse = try await request("/api/hm/models", body: m.dict(), method: "POST")
        return d.error ?? "OK"
    }
    func updateModel(_ m: ModelInfo) async throws -> String {
        let d: HMResponse = try await request("/api/hm/models/" + m.id, body: m.dict(), method: "PUT")
        return d.error ?? "OK"
    }
    func deleteModel(_ id: String) async throws -> String {
        let d: HMResponse = try await request("/api/hm/models/" + id, method: "DELETE")
        return d.error ?? "OK"
    }
    func testModel(_ m: ModelInfo) async throws -> (ok: Bool, message: String, latency: Int, reply: String) {
        let d: TestConnectResponse = try await request("/api/hm/test-connect", body: [
            "base_url": m.base_url, "api_key": m.api_key,
            "model": m.model, "api_mode": m.api_mode ?? "chat_completions"
        ], method: "POST")
        let msg = d.message ?? d.error ?? (d.ok == true ? "连通正常" : "测试失败")
        return (d.ok == true, msg, d.latency ?? 0, d.reply ?? "")
    }

    // 通过 base_url + key 获取上游模型列表
    func fetchUpstreamModels(baseURL: String, apiKey: String) async throws -> [String] {
        let d: FetchModelsResponse = try await request("/api/hm/fetch-models", body: [
            "base_url": baseURL, "api_key": apiKey
        ], method: "POST")
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return d.models ?? []
    }

    // ---------- Codex ----------
    func fetchCodexConfig() async throws -> CodexConfig {
        try await request("/api/hm/codex")
    }
    func applyCodexModel(modelID: String) async throws -> String {
        let d: CodexResponse = try await request("/api/hm/codex", body: ["model_id": modelID], method: "POST")
        return d.message ?? d.error ?? "OK"
    }

    // ---------- Dashboard 网页会话 ----------
    func dashboardStatus() async throws -> Bool {
        let d: DashboardResponse = try await request("/api/hm/dashboard")
        return d.running ?? false
    }
    func dashboardAction(_ action: String) async throws -> (running: Bool, message: String) {
        let d: DashboardResponse = try await request("/api/hm/dashboard", body: ["action": action], method: "POST")
        return (d.running ?? false, d.message ?? d.error ?? "OK")
    }

    // ---------- 底层 ----------
    private func request<T: Codable>(_ path: String, body: [String: Any]? = nil, method: String = "GET") async throws -> T {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = method
        req.timeoutInterval = 25
        if let t = token { req.setValue(t, forHTTPHeaderField: "x-token") }
        if let b = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: b)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.network }
        if http.statusCode == 401 { throw APIError.unauthorized }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension ModelInfo {
    func dict() -> [String: Any] {
        [
            "id": id, "name": name, "model": model,
            "base_url": base_url, "api_key": api_key,
            "api_mode": api_mode ?? "chat_completions"
        ]
    }
}

enum APIError: Error, LocalizedError {
    case network, unauthorized
    case message(String)
    var errorDescription: String? {
        switch self {
        case .network: return "网络错误"
        case .unauthorized: return "未登录"
        case .message(let m): return m
        }
    }
}