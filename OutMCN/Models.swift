import Foundation

// ---------- 通用 ----------
struct LoginResponse: Codable {
    let token: String?
    let expire: Int?
    let error: String?
}

// ---------- 网关设置 (HM) ----------
struct GatewayInfo: Codable, Identifiable {
    let name: String?
    let service: String
    let config_path: String?
    let status: String?
    let model: GatewayModel?
    var id: String { service }
}

struct GatewayModel: Codable {
    let model: String?
    let base_url: String?
    let api_mode: String?
}

struct ModelInfo: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var model: String
    var base_url: String
    var api_key: String
    var api_mode: String?

    init(id: String, name: String, model: String, base_url: String, api_key: String, api_mode: String? = nil) {
        self.id = id; self.name = name; self.model = model
        self.base_url = base_url; self.api_key = api_key; self.api_mode = api_mode
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        base_url = try c.decodeIfPresent(String.self, forKey: .base_url) ?? ""
        api_key = try c.decodeIfPresent(String.self, forKey: .api_key) ?? ""
        api_mode = try c.decodeIfPresent(String.self, forKey: .api_mode)
    }
}

struct HMResponse: Codable {
    let ok: Bool?
    let error: String?
    let gateways: [GatewayInfo]?
    let models: [ModelInfo]?
    let status: String?
    let message: String?
}

// ---------- 邮件系统 (Mail) ----------
struct Mailbox: Codable, Identifiable {
    let email: String
    let price: String?
    let started_at: String?
    let status: String?
    let deleted: Bool?
    var id: String { email }
}

struct MailListResponse: Codable {
    let ok: Bool?
    let error: String?
    let items: [Mailbox]?
    let total: Int?
    let used_count: Int?
    let available_count: Int?
}

struct MailSyncResponse: Codable {
    let ok: Bool?
    let error: String?
    let total: Int?
    let db_count: Int?
    let new_items: Int?
}

struct MailItem: Codable {
    let received_at: String?
    let code_match: String?
}

struct ReceiveResponse: Codable {
    let code: String?
    let msg: String?
    let error: String?
    let data: [MailItem]?
}

struct Empty: Codable {}