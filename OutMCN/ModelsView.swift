import SwiftUI
import UIKit

struct ModelsTabView: View {
    var body: some View {
        ModelsContentView()
    }
}

struct ModelsContentView: View {
    @State private var models: [ModelInfo] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var showForm = false
    @State private var editing: ModelInfo?
    @State private var isDuplicate = false // 复制模式：预填字段但作为新模型
    @State private var busyID: String?
    @State private var toast: (String, Bool)? // (text, isError)
    @State private var pendingDelete: ModelInfo?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                // 顶部居中标题
                HStack {
                    Spacer()
                    Text("模型")
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
                } else if models.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "cpu").font(.largeTitle).foregroundColor(.secondary)
                        Text("暂无模型").foregroundColor(.secondary)
                        Text("点右上角 + 添加模型").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(models) { m in
                                modelCard(m)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .sheet(isPresented: $showForm) {
            ModelFormView(model: editing, isDuplicate: isDuplicate) { saved in
                showForm = false
                toast = (saved, saved.contains("失败"))
                load()
            }
        }
        .overlay(toastOverlay)
        .confirmationDialog(
            pendingDelete == nil ? "" : "确定删除模型 \(pendingDelete!.name)？",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let m = pendingDelete {
                    remove(m)
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .onAppear { load() }
        .onReceive(NotificationCenter.default.publisher(for: .outmcnRefreshModels)) { _ in
            load()
        }
    }

    // 每个模型一张独立卡片
    private func modelCard(_ m: ModelInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 名称单行不换行 + API 模式靠右
            HStack(spacing: 8) {
                Text(m.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(m.api_mode ?? "")
                    .font(.system(size: 11))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15)).cornerRadius(6)
                    .foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("模型 ID：\(m.model)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(m.base_url)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Divider()
            // 底部按钮行：测试 复制 编辑 删除 靠右
            HStack(spacing: 10) {
                Spacer()
                Button {
                    test(m)
                } label: {
                    if busyID == m.id {
                        ProgressView().scaleEffect(0.6).frame(height: 16)
                    } else {
                        Text("测试").font(.system(size: 12))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(busyID == m.id)

                Button {
                    duplicate(m)
                } label: {
                    Text("复制").font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    edit(m)
                } label: {
                    Text("编辑").font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    pendingDelete = m
                } label: {
                    Text("删除").font(.system(size: 12)).foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
        isDuplicate = false
        showForm = true
    }

    private func duplicate(_ m: ModelInfo) {
        // 拷贝一个相同的模型到添加模型表单（可修改后保存）
        editing = m
        isDuplicate = true
        showForm = true
    }

    private func remove(_ m: ModelInfo) {
        busyID = m.id
        Task {
            do {
                _ = try await APIClient.shared.deleteModel(m.id)
                DispatchQueue.main.async {
                    busyID = nil
                    toast = ("已删除 \(m.name)", false)
                    load()
                }
            } catch {
                DispatchQueue.main.async { busyID = nil; toast = (error.localizedDescription, true) }
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
                    if r.ok {
                        toast = ("连通正常 \(r.latency)ms", false)
                    } else {
                        toast = (r.message, true)
                    }
                }
            } catch {
                DispatchQueue.main.async { busyID = nil; toast = (error.localizedDescription, true) }
            }
        }
    }
}

// ---------- 添加/编辑模型表单 ----------
struct ModelFormView: View {
    let model: ModelInfo?
    let isDuplicate: Bool
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
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        // 基本信息卡片
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("名称").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                                TextField("名称", text: $name)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 15))
                                    .autocorrectionDisabled()
                            }
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))

                        // 模型 ID 卡片（标签+下拉同一行）
                        VStack(spacing: 12) {
                            HStack {
                                Text("模型 ID")
                                    .font(.system(size: 15))
                                Spacer()
                                Picker("", selection: $modelID) {
                                    Text(modelOptions.isEmpty ? "请先获取模型" : "请选择").tag("")
                                    ForEach(modelOptions, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                                .disabled(modelOptions.isEmpty)
                            }
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))

                        // 连接卡片
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Base URL").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                                TextField("Base URL", text: $baseURL)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 15))
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .autocapitalization(.none)
                            }
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("API Key").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                                SecureField("API Key", text: $apiKey)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(.system(size: 15))
                                    .autocorrectionDisabled()
                            }
                            Divider()
                            Button {
                                fetchModels()
                            } label: {
                                Group {
                                    if fetching {
                                        ProgressView()
                                    } else {
                                        Text("获取模型").font(.system(size: 15, weight: .semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .disabled(fetching || baseURL.trimmingCharacters(in: .whitespaces).isEmpty)
                            Divider()
                            HStack {
                                Text("API 模式").font(.system(size: 15))
                                Spacer()
                                Picker("", selection: $apiMode) {
                                    ForEach(modes, id: \.self) { Text($0) }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.25), lineWidth: 1))

                        if let e = errorMsg {
                            Text(e)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(model == nil ? (isDuplicate ? "复制模型" : "添加模型") : "编辑模型")
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
        // id：编辑时保留原 id；添加/复制时留空由后端生成（m+时间戳）
        let info = ModelInfo(id: (model != nil && !isDuplicate) ? model!.id : "",
                             name: name, model: modelID,
                             base_url: baseURL, api_key: apiKey, api_mode: apiMode)
        Task {
            do {
                let msg: String
                if model == nil || isDuplicate {
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