import SwiftUI

struct GatewaysTabView: View {
    var body: some View {
        GatewaysContentView()
    }
}

struct GatewaysContentView: View {
    @State private var gateways: [GatewayInfo] = []
    @State private var models: [ModelInfo] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var busyService: String?
    @State private var toast: (String, Bool)?
    @State private var pendingAction: (service: String, name: String, action: String)?

    // ---- Codex ----
    @State private var codexModel: String = ""
    @State private var codexProvider: String = ""
    @State private var codexReasoning: String = ""
    @State private var selectedCodexID: String = ""
    @State private var applying = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                // 顶部居中标题
                HStack {
                    Spacer()
                    Text("网关")
                        .font(.system(size: 20, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                if loading {
                    Spacer()
                    HStack { Spacer(); ProgressView(); Spacer() }
                    Spacer()
                } else if let e = errorMsg {
                    Spacer()
                    VStack { Text("加载失败").font(.headline); Text(e).font(.footnote).foregroundColor(.secondary) }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(gateways) { g in
                                gatewayCard(g)
                            }
                            codexCard
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .overlay(toastOverlay)
        .confirmationDialog(
            pendingAction == nil ? "" : (pendingAction!.action == "stop" ? "确定停止网关 \(pendingAction!.name)？" : "确定重启网关 \(pendingAction!.name)？"),
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible
        ) {
            Button(pendingAction?.action == "stop" ? "停止" : "重启", role: .destructive) {
                if let p = pendingAction {
                    act(p.service, action: p.action)
                }
                pendingAction = nil
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        }
        .onAppear { loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .outmcnRefreshGateways)) { _ in
            loadAll()
        }
    }

    // 每个网关一张独立卡片
    private func gatewayCard(_ g: GatewayInfo) -> some View {
        let online = g.status == "active"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(online ? Color.green : Color.red).frame(width: 9, height: 9)
                Text(g.name ?? g.service).font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(online ? "运行中" : "已停止")
                    .font(.system(size: 13))
                    .foregroundColor(online ? .green : .red)
            }
            if let gm = g.model, let mid = gm.model, !mid.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("模型 ID：\(mid)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let bu = gm.base_url, !bu.isEmpty {
                        Text(bu)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            // 下拉框 + 切换 + 停止 + 重启 同一行
            HStack(spacing: 8) {
                Picker("模型", selection: switchSelection(for: g)) {
                    Text("选择模型").tag("")
                    ForEach(models) { m in
                        Text("\(m.name) - \(m.model)").tag(m.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity)
                .disabled(busyService == g.service)

                Button {
                    let sid = switchSelection(for: g)
                    guard !sid.wrappedValue.isEmpty else { return }
                    act(g.service, action: "switch", modelID: sid.wrappedValue)
                } label: {
                    Text("切换")
                        .font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .disabled(busyService == g.service || switchSelection(for: g).wrappedValue.isEmpty)

                Button(online ? "停止" : "启动") {
                    if online {
                        pendingAction = (g.service, g.name ?? g.service, "stop")
                    } else {
                        act(g.service, action: "start")
                    }
                }
                .font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(.secondarySystemBackground).opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
                .cornerRadius(8)
                .disabled(busyService == g.service)

                Button("重启") {
                    pendingAction = (g.service, g.name ?? g.service, "restart")
                }
                .font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(.secondarySystemBackground).opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.35)))
                .cornerRadius(8)
                .disabled(busyService == g.service || !online)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }

    // Codex 也是独立卡片
    private var codexCard: some View {
        // 当前 Codex 模型对应 base_url（models 里按 model 匹配）
        let currentEntry = models.first { $0.model == codexModel }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(Color.green).frame(width: 9, height: 9)
                Text("Codex").font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            if !codexModel.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("模型 ID：\(codexModel)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let bu = currentEntry?.base_url, !bu.isEmpty {
                        Text(bu)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if models.isEmpty {
                Text("暂无模型，请先在「模型」页添加").foregroundColor(.secondary)
            } else {
                HStack(spacing: 10) {
                    Picker("模型", selection: $selectedCodexID) {
                        Text("选择模型").tag("")
                        ForEach(models) { m in
                            Text("\(m.name) - \(m.model)").tag(m.id)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(applying)

                    Button {
                        applyCodex()
                    } label: {
                        if applying {
                            ProgressView().scaleEffect(0.8)
                                .frame(minWidth: 46, minHeight: 30)
                        } else {
                            Text("应用").font(.system(size: 13))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .disabled(applying || selectedCodexID.isEmpty)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.05), radius: 6, y: 2)
    }

    @ViewBuilder private var toastOverlay: some View {
        if let t = toast {
            Text(t.0).font(.system(size: 13)).foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(t.1 ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
                .cornerRadius(10)
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { self.toast = nil }
                    }
                }
        }
    }

    private func loadAll() {
        loading = true; errorMsg = nil
        Task {
            do {
                async let gws = APIClient.shared.fetchGateways()
                async let ms = APIClient.shared.fetchModels()
                async let cx = APIClient.shared.fetchCodexConfig()
                let (gwResult, modelList, codex) = try await (gws, ms, cx)
                DispatchQueue.main.async {
                    gateways = gwResult.gateways
                    models = modelList
                    codexModel = codex.model ?? ""
                    codexProvider = codex.provider ?? ""
                    codexReasoning = codex.reasoning ?? ""
                    selectedCodexID = ""
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
                    toast = (msg, msg.contains("失败"))
                    loadAll()
                }
            } catch {
                DispatchQueue.main.async {
                    busyService = nil
                    toast = (error.localizedDescription, true)
                }
            }
        }
    }

    private func applyCodex() {
        guard !selectedCodexID.isEmpty else { return }
        applying = true
        Task {
            do {
                let msg = try await APIClient.shared.applyCodexModel(modelID: selectedCodexID)
                DispatchQueue.main.async {
                    applying = false
                    toast = (msg, msg.contains("失败"))
                    loadAll()
                }
            } catch {
                DispatchQueue.main.async {
                    applying = false
                    toast = (error.localizedDescription, true)
                }
            }
        }
    }

    // 每个网关一行的切换模型选中态（Dictionary @State）
    @State private var switchSelections: [String: String] = [:]
    private func switchSelection(for g: GatewayInfo) -> Binding<String> {
        Binding(
            get: { switchSelections[g.service] ?? "" },
            set: { switchSelections[g.service] = $0 }
        )
    }
}