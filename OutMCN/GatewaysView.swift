import SwiftUI

struct GatewaysTabView: View {
    var body: some View {
        NavigationView {
            GatewaysContentView()
        }
        .navigationViewStyle(.stack)
    }
}

struct GatewaysContentView: View {
    @State private var gateways: [GatewayInfo] = []
    @State private var models: [ModelInfo] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var busyService: String?
    @State private var toast: String?

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 40)
            } else if let e = errorMsg {
                VStack { Text("加载失败").font(.headline); Text(e).font(.footnote).foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                Section(header: Text("网关")) {
                    ForEach(gateways) { g in
                        GatewayRow(gateway: g, models: models, busy: busyService == g.service) { action, mid in
                            act(g.service, action: action, modelID: mid)
                        }
                    }
                }
                Section(header: Text("模型")) {
                    if models.isEmpty {
                        Text("暂无模型").foregroundColor(.secondary)
                    } else {
                        ForEach(models) { m in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.name).font(.body)
                                    Text(m.model).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(m.api_mode ?? "")
                                    .font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.15)).cornerRadius(6)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("网关设置")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { load() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .overlay(toastOverlay)
        .onAppear { load() }
    }

    @ViewBuilder private var toastOverlay: some View {
        if let t = toast {
            Text(t).font(.system(size: 13)).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.black.opacity(0.75)).cornerRadius(10)
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { self.toast = nil }
                    }
                }
        }
    }

    private func load() {
        loading = true; errorMsg = nil
        Task {
            do {
                let r = try await APIClient.shared.fetchGateways()
                DispatchQueue.main.async {
                    gateways = r.gateways
                    models = r.models
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

    private func act(_ service: String, action: String, modelID: String? = nil) {
        busyService = service
        Task {
            do {
                let msg: String
                if action == "switch", let mid = modelID {
                    msg = try await APIClient.shared.applyModel(gateway: service, modelID: mid)
                } else {
                    msg = try await APIClient.shared.gatewayService(service, action: action)
                }
                DispatchQueue.main.async {
                    busyService = nil
                    toast = msg
                    load()
                }
            } catch {
                DispatchQueue.main.async {
                    busyService = nil
                    toast = error.localizedDescription
                }
            }
        }
    }
}

struct GatewayRow: View {
    let gateway: GatewayInfo
    let models: [ModelInfo]
    let busy: Bool
    let onAction: (String, String?) -> Void

    @State private var selectedModel: String = ""

    var online: Bool { gateway.status == "active" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(online ? Color.green : Color.red).frame(width: 9, height: 9)
                Text(gateway.name ?? gateway.service).font(.headline)
                Spacer()
                Text(online ? "运行中" : "已停止")
                    .font(.caption).foregroundColor(online ? .green : .red)
            }
            if let m = gateway.model, !m.isEmpty {
                Text("当前模型：\(m)").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Picker("模型", selection: $selectedModel) {
                    Text("选择模型").tag("")
                    ForEach(models) { m in
                        Text("\(m.name)").tag(m.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity)
                .disabled(busy)

                Button("切换") {
                    guard !selectedModel.isEmpty else { return }
                    onAction("switch", selectedModel)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || selectedModel.isEmpty)

                Button(online ? "停止" : "启动") {
                    onAction(online ? "stop" : "start", nil)
                }
                .buttonStyle(.bordered)
                .disabled(busy)

                Button("重启") { onAction("restart", nil) }
                    .buttonStyle(.bordered)
                    .disabled(busy || !online)
            }
        }
        .padding(.vertical, 4)
    }
}