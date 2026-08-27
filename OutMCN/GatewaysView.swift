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

    // ---- Codex ----
    @State private var codexModel: String = ""
    @State private var codexProvider: String = ""
    @State private var codexReasoning: String = ""
    @State private var selectedCodexID: String = ""
    @State private var applying = false

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
                        gatewayRow(g)
                    }
                }
                Section(header: Text("Codex")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(Color.green).frame(width: 9, height: 9)
                            Text("Codex").font(.headline)
                            Spacer()
                            if !codexModel.isEmpty {
                                Text("当前模型：\(codexModel)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        if models.isEmpty {
                            Text("暂无模型，请先在「模型」页添加").foregroundColor(.secondary)
                        } else {
                            HStack(spacing: 10) {
                                Picker("模型", selection: $selectedCodexID) {
                                    Text("选择模型").tag("")
                                    ForEach(models) { m in
                                        Text("\(m.name)").tag(m.id)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: .infinity)
                                .disabled(applying)

                                Button {
                                    applyCodex()
                                } label: {
                                    Group {
                                        if applying {
                                            ProgressView().scaleEffect(0.7)
                                        } else {
                                            Text("应用").font(.system(size: 13))
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .disabled(applying || selectedCodexID.isEmpty)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("网关")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { loadAll() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .overlay(toastOverlay)
        .onAppear { loadAll() }
    }

    private func gatewayRow(_ g: GatewayInfo) -> some View {
        let online = g.status == "active"
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(online ? Color.green : Color.red).frame(width: 9, height: 9)
                Text(g.name ?? g.service).font(.headline)
                Spacer()
                Text(online ? "运行中" : "已停止")
                    .font(.caption).foregroundColor(online ? .green : .red)
            }
            if let m = g.model?.model, !m.isEmpty {
                Text("当前模型：\(m)").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Picker("模型", selection: switchSelection(for: g)) {
                    Text("选择模型").tag("")
                    ForEach(models) { m in
                        Text("\(m.name)").tag(m.id)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity)
                .disabled(busyService == g.service)

                Button("切换") {
                    let sid = switchSelection(for: g)
                    guard !sid.wrappedValue.isEmpty else { return }
                    act(g.service, action: "switch", modelID: sid.wrappedValue)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busyService == g.service || switchSelection(for: g).wrappedValue.isEmpty)

                Button(online ? "停止" : "启动") {
                    act(g.service, action: online ? "stop" : "start")
                }
                .buttonStyle(.bordered)
                .disabled(busyService == g.service)

                Button("重启") { act(g.service, action: "restart") }
                    .buttonStyle(.bordered)
                    .disabled(busyService == g.service || !online)
            }
        }
        .padding(.vertical, 4)
    }

    // 每个网关一行的切换模型选中态（Dictionary @State）
    @State private var switchSelections: [String: String] = [:]
    private func switchSelection(for g: GatewayInfo) -> Binding<String> {
        Binding(
            get: { switchSelections[g.service] ?? "" },
            set: { switchSelections[g.service] = $0 }
        )
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
                    toast = msg
                    loadAll()
                }
            } catch {
                DispatchQueue.main.async {
                    busyService = nil
                    toast = error.localizedDescription
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
                    toast = msg
                    loadAll()
                }
            } catch {
                DispatchQueue.main.async {
                    applying = false
                    toast = error.localizedDescription
                }
            }
        }
    }
}