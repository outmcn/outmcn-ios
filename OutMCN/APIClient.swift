import Foundation

/// OutMCN API 客户端：x-token 认证（同网页端）
class APIClient {
    static let shared = APIClient()
    let baseURL = "https://outmcn.net"

    // 会话失效通知（401 时由网络层发布，根视图监听后跳登录页）
    static let sessionExpiredNotification = Notification.Name("outmcn.session.expired")

    private let tokenKey = "outmcn_token"
    var token: String? {
        get { KeychainStore.load(tokenKey) }
        set {
            if let v = newValue { KeychainStore.save(v, key: tokenKey) }
            else { KeychainStore.delete(tokenKey) }
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
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return d.message ?? "OK"
    }
    func applyModel(gateway: String, modelID: String) async throws -> String {
        let d: HMResponse = try await request("/api/hm/apply", body: ["gateway": gateway, "model_id": modelID], method: "POST")
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return d.message ?? "OK"
    }
    func fetchModels() async throws -> [ModelInfo] {
        let d: HMResponse = try await request("/api/hm/models")
        return d.models ?? []
    }
    // 编辑/复制时获取完整模型（含完整 api_key，列表已脱敏）
    func fetchFullModel(id: String) async throws -> ModelInfo {
        let d: FullModelResponse = try await request("/api/hm/models/full", body: ["id": id], method: "POST")
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        guard let m = d.model else { throw APIError.message("模型不存在") }
        return m
    }
    func createModel(_ m: ModelInfo) async throws -> String {
        let d: HMResponse = try await request("/api/hm/models", body: m.dict(), method: "POST")
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return "已添加"
    }
    func updateModel(_ m: ModelInfo) async throws -> String {
        let id = m.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? m.id
        let d: HMResponse = try await request("/api/hm/models/" + id, body: m.dict(), method: "PUT")
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return "已保存"
    }
    func deleteModel(_ id: String) async throws -> String {
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let d: HMResponse = try await request("/api/hm/models/" + enc, method: "DELETE")
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return "已删除"
    }
    func testModel(_ m: ModelInfo) async throws -> (ok: Bool, message: String, latency: Int, reply: String) {
        // 模型列表中的 api_key 已脱敏，测试前必须取完整配置
        let full = try await fetchFullModel(id: m.id)
        let d: TestConnectResponse = try await request("/api/hm/test-connect", body: [
            "base_url": full.base_url, "api_key": full.api_key,
            "model": full.model, "api_mode": full.api_mode ?? "chat_completions"
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
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return d.message ?? "OK"
    }

    // ---------- Dashboard 网页会话 ----------
    func dashboardStatus() async throws -> Bool {
        let d: DashboardResponse = try await request("/api/hm/dashboard")
        return d.running ?? false
    }
    func dashboardAction(_ action: String) async throws -> (running: Bool, message: String) {
        let d: DashboardResponse = try await request("/api/hm/dashboard", body: ["action": action], method: "POST")
        if let e = d.error, !e.isEmpty { throw APIError.message(e) }
        return (d.running ?? false, d.message ?? "OK")
    }

    // ---------- 底层 ----------
    private func request<T: Codable>(_ path: String, body: [String: Any]? = nil, method: String = "GET") async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.message("URL 无效") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 25
        if let t = token { req.setValue(t, forHTTPHeaderField: "x-token") }
        if let b = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: b)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.network }
        // 401：会话失效 → 清 token + 通知根视图跳登录页
        if http.statusCode == 401 {
            token = nil
            NotificationCenter.default.post(name: APIClient.sessionExpiredNotification, object: nil)
            throw APIError.unauthorized
        }
        // 非 2xx：尝试解析服务端 error 字段，给出真实原因
        guard (200..<300).contains(http.statusCode) else {
            if let errObj = try? JSONDecoder().decode(ErrorBody.self, from: data), let e = errObj.error, !e.isEmpty {
                throw APIError.message(e)
            }
            throw APIError.message("服务错误（HTTP \(http.statusCode)）")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct ErrorBody: Codable {
    let error: String?
}

struct FullModelResponse: Codable {
    let ok: Bool?
    let error: String?
    let model: ModelInfo?
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
        case .unauthorized: return "已退出登录"
        case .message(let m): return m
        }
    }
}