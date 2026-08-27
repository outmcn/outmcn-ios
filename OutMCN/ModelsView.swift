import SwiftUI

struct ModelsTabView: View {
    var body: some View {
        NavigationView {
            ModelsContentView()
        }
        .navigationViewStyle(.stack)
    }
}

struct ModelsContentView: View {
    @State private var models: [ModelInfo] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var showForm = false
    @State private var editing: ModelInfo?
    @State private var busyID: String?
    @State private var toast: String?

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 40)
            } else if let e = errorMsg {
                VStack { Text("加载失败").font(.headline); Text(e).font(.footnote).foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if models.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "cpu").font(.largeTitle).foregroundColor(.secondary)
                    Text("暂无模型").foregroundColor(.secondary)
                    Text("点右上角 + 添加模型").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ForEach(models) { m in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.name).font(.body)
                            Text(m.model).font(.caption).foregroundColor(.secondary)
                            Text(m.base_url).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(m.api_mode ?? "")
                                .font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.blue.opacity(0.15)).cornerRadius(6)
                                .foregroundColor(.blue)
                            HStack(spacing: 12) {
                                Button("测试") { test(m) }
                                    .font(.caption)
                                    .disabled(busyID == m.id)
                                Button("编辑") { edit(m) }
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) { remove(m) }
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("模型")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                    Button { editing = nil; showForm = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showForm) {
            ModelFormView(model: editing) { saved in
                showForm = false
                toast = saved
                load()
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
                let list = try await APIClient.shared.fetchModels()
                DispatchQueue.main.async { models = list; loading = false }
            } catch {
                DispatchQueue.main.async { errorMsg = error.localizedDescription; loading = false }
            }
        }
    }

    private func edit(_ m: ModelInfo) {
        editing = m
        showForm = true
    }

    private func remove(_ m: ModelInfo) {
        busyID = m.id
        Task {
            do {
                _ = try await APIClient.shared.deleteModel(m.id)
                DispatchQueue.main.async {
                    busyID = nil
                    toast = "已删除 \(m.name)"
                    load()
                }
            } catch {
                DispatchQueue.main.async { busyID = nil; toast = error.localizedDescription }
            }
        }
    }

    private func test(_ m: ModelInfo) {
        busyID = m.id
        Task {
            do {
                let msg = try await APIClient.shared.testModel(m)
                DispatchQueue.main.async { busyID = nil; toast = "\(m.name)：\(msg)" }
            } catch {
                DispatchQueue.main.async { busyID = nil; toast = error.localizedDescription }
            }
        }
    }
}

// ---------- 添加/编辑模型表单 ----------
struct ModelFormView: View {
    let model: ModelInfo?
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var modelID = ""
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var apiMode = "chat_completions"
    @State private var saving = false
    @State private var errorMsg: String?

    private let modes = ["chat_completions", "responses"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("名称（如：TBTK）", text: $name)
                        .autocorrectionDisabled()
                    TextField("模型 ID（如：gpt-5.6-sol）", text: $modelID)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                Section(header: Text("连接")) {
                    TextField("Base URL（如：https://tbtk.asia/v1）", text: $baseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    SecureField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                    Picker("API 模式", selection: $apiMode) {
                        ForEach(modes, id: \.self) { Text($0) }
                    }
                }
                if let e = errorMsg {
                    Section {
                        Text(e).font(.footnote).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(model == nil ? "添加模型" : "编辑模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") { save() }
                        .disabled(saving)
                }
            }
            .onAppear {
                if let m = model {
                    name = m.name
                    modelID = m.id
                    baseURL = m.base_url
                    apiKey = m.api_key
                    apiMode = m.api_mode ?? "chat_completions"
                }
            }
        }
    }

    private func save() {
        guard !name.isEmpty, !modelID.isEmpty else {
            errorMsg = "名称和模型 ID 必填"; return
        }
        errorMsg = nil
        saving = true
        // id：新建时留空由后端生成（m+时间戳）；编辑时保留原 id
        let info = ModelInfo(id: model?.id ?? "", name: name, model: modelID,
                             base_url: baseURL, api_key: apiKey, api_mode: apiMode)
        Task {
            do {
                let msg: String
                if model == nil {
                    msg = try await APIClient.shared.createModel(info)
                } else {
                    msg = try await APIClient.shared.updateModel(info)
                }
                DispatchQueue.main.async {
                    saving = false
                    onDone(msg)
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    saving = false
                    errorMsg = error.localizedDescription
                }
            }
        }
    }
}