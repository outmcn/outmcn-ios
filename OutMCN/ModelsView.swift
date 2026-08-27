import SwiftUI
import UIKit

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
                            Text(m.name).font(.body).fontWeight(.medium)
                            Text("模型 ID：\(m.model)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(m.base_url)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(m.api_mode ?? "")
                                .font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.blue.opacity(0.15)).cornerRadius(6)
                                .foregroundColor(.blue)
                            HStack(spacing: 8) {
                                Button {
                                    copyModelID(m)
                                } label: {
                                    Image(systemName: "doc.on.doc").font(.system(size: 13))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("编辑") { edit(m) }
                                    .font(.system(size: 13))
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                Button {
                                    test(m)
                                } label: {
                                    if busyID == m.id {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Text("测试").font(.system(size: 13))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(busyID == m.id)
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

    private func copyModelID(_ m: ModelInfo) {
        UIPasteboard.general.string = m.model
        toast = "已复制模型 ID：\(m.model)"
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
                let r = try await APIClient.shared.testModel(m)
                DispatchQueue.main.async {
                    busyID = nil
                    toast = r.ok
                        ? "✓ \(m.name)：\(r.message) (\(r.latency)ms)"
                        : "✗ \(m.name)：\(r.message)"
                }
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
    @State private var modelOptions: [String] = []
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var apiMode = "chat_completions"
    @State private var fetching = false
    @State private var saving = false
    @State private var errorMsg: String?

    private let modes = ["chat_completions", "responses"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("名称（如：TBTK）", text: $name)
                        .autocorrectionDisabled()
                    if modelID.isEmpty && modelOptions.isEmpty {
                        Text("请先填写下方 Base URL 和 API Key，点「获取模型」选择模型 ID").font(.caption).foregroundColor(.secondary)
                    }
                }
                Section(header: Text("模型 ID（从获取结果中选择）")) {
                    Picker("模型 ID", selection: $modelID) {
                        Text(modelOptions.isEmpty ? "请先获取模型" : "请选择").tag("")
                        ForEach(modelOptions, id: \.self) { Text($0) }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .disabled(modelOptions.isEmpty)
                }
                Section(header: Text("连接")) {
                    TextField("Base URL（如：https://tbtk.asia/v1）", text: $baseURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    SecureField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                    Button {
                        fetchModels()
                    } label: {
                        Group {
                            if fetching {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("获取模型").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .disabled(fetching || baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
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
                        .disabled(saving || modelID.isEmpty)
                }
            }
            .onAppear {
                if let m = model {
                    name = m.name
                    modelID = m.model
                    modelOptions = [m.model]
                    baseURL = m.base_url
                    apiKey = m.api_key
                    apiMode = m.api_mode ?? "chat_completions"
                }
            }
        }
    }

    private func fetchModels() {
        let url = baseURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { errorMsg = "请先填写 Base URL"; return }
        errorMsg = nil
        fetching = true
        Task {
            do {
                let list = try await APIClient.shared.fetchUpstreamModels(baseURL: url, apiKey: apiKey)
                DispatchQueue.main.async {
                    fetching = false
                    if list.isEmpty {
                        errorMsg = "未获取到模型列表"
                    } else {
                        modelOptions = list
                        modelID = list.count == 1 ? list[0] : modelID
                        if !list.contains(modelID) { modelID = "" }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    fetching = false
                    errorMsg = error.localizedDescription
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