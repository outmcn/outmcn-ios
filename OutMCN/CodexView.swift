import SwiftUI

struct CodexTabView: View {
    var body: some View {
        NavigationView {
            CodexContentView()
        }
        .navigationViewStyle(.stack)
    }
}

struct CodexContentView: View {
    @State private var models: [ModelInfo] = []
    @State private var currentModel: String = ""
    @State private var provider: String = ""
    @State private var reasoning: String = ""
    @State private var selectedID: String = ""
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var applying = false
    @State private var toast: String?

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 40)
            } else if let e = errorMsg {
                VStack { Text("加载失败").font(.headline); Text(e).font(.footnote).foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                Section(header: Text("Codex 当前配置")) {
                    row("当前模型", currentModel.isEmpty ? "-" : currentModel)
                    row("Provider", provider.isEmpty ? "-" : provider)
                    if !reasoning.isEmpty {
                        row("推理强度", reasoning)
                    }
                }
                Section(header: Text("切换模型")) {
                    if models.isEmpty {
                        Text("暂无模型，请先在网页端添加").foregroundColor(.secondary)
                    } else {
                        Picker("选择模型", selection: $selectedID) {
                            Text("请选择模型").tag("")
                            ForEach(models) { m in
                                Text("\(m.name)（\(m.model)）").tag(m.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())

                        Button {
                            apply()
                        } label: {
                            Group {
                                if applying {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Text("应用并重启 Codex").frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .disabled(applying || selectedID.isEmpty)

                        if let m = models.first(where: { $0.id == selectedID }) {
                            Text("将写入 config.toml：model=\(m.model)，并重启用新模型")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Codex")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { load() } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .overlay(toastOverlay)
        .onAppear { load() }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundColor(.secondary)
            Spacer()
            Text(v).fontWeight(.medium)
        }
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
                async let cf = APIClient.shared.fetchCodexConfig()
                async let ms = APIClient.shared.fetchModels()
                let (cfg, models) = try await (cf, ms)
                DispatchQueue.main.async {
                    self.models = models
                    currentModel = cfg.model ?? ""
                    provider = cfg.provider ?? ""
                    reasoning = cfg.reasoning ?? ""
                    selectedID = ""
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

    private func apply() {
        guard !selectedID.isEmpty else { return }
        applying = true
        Task {
            do {
                let msg = try await APIClient.shared.applyCodexModel(modelID: selectedID)
                DispatchQueue.main.async {
                    applying = false
                    toast = msg
                    load()
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