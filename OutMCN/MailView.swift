import SwiftUI

struct MailTabView: View {
    var body: some View {
        NavigationView {
            MailContentView()
        }
        .navigationViewStyle(.stack)
    }
}

struct MailContentView: View {
    enum MailTab: String, CaseIterable { case avail = "可用", used = "已用" }

    @State private var list: [Mailbox] = []
    @State private var availCount = 0
    @State private var usedCount = 0
    @State private var tab: MailTab = .avail
    @State private var search = ""
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var syncing = false
    @State private var receiving = ""
    @State private var receiveResult: PresentableResult?
    @State private var toast: String?

    struct PresentableResult: Identifiable {
        let id = UUID()
        let title: String
        let lines: [(time: String, code: String)]
    }

    var filtered: [Mailbox] {
        let items = list.filter { tab == .used ? ($0.deleted ?? false) : !($0.deleted ?? false) }
        guard !search.isEmpty else { return items }
        return items.filter { $0.email.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索 + 同步
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索邮箱…", text: $search)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                Button {
                    Task { await doSync() }
                } label: {
                    Group {
                        if syncing { ProgressView() }
                        else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                }
                .disabled(syncing)
            }
            .padding(.horizontal).padding(.vertical, 10)

            // Tab
            HStack(spacing: 10) {
                tabButton(.avail, label: "可用 \(availCount)")
                tabButton(.used, label: "已用 \(usedCount)")
                Spacer()
            }
            .padding(.horizontal)

            // 列表
            if loading {
                Spacer(); ProgressView("加载中…"); Spacer()
            } else if let e = errorMsg {
                Spacer(); VStack { Text("加载失败").font(.headline); Text(e).font(.footnote).foregroundColor(.secondary) }; Spacer()
            } else if filtered.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.largeTitle).foregroundColor(.secondary)
                    Text("暂无邮箱").foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filtered) { m in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.email).font(.system(.body, design: .monospaced))
                                if let t = m.started_at, !t.isEmpty {
                                    Text(t).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if tab == .avail {
                                Button("收件") { receive(m.email) }
                                    .buttonStyle(.bordered).controlSize(.small)
                                Button("已用") {
                                    Task { await doMarkUsed(m.email) }
                                }
                                .buttonStyle(.borderless).controlSize(.small)
                            } else {
                                Button("收件") { receive(m.email) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("邮件系统")
        .sheet(item: $receiveResult) { r in
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(r.lines.enumerated()), id: \.offset) { _, line in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(line.time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(line.code.isEmpty ? "未提取到验证码" : line.code)
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .foregroundColor(line.code.isEmpty ? .secondary : .green)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .navigationTitle(r.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { receiveResult = nil }
                    }
                }
            }
        }
        .overlay(toastOverlay)
        .onAppear { load() }
    }

    @ViewBuilder private func tabButton(_ t: MailTab, label: String) -> some View {
        Button(label) {
            withAnimation { tab = t }
        }
        .font(.system(size: 13, weight: tab == t ? .semibold : .regular))
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background(tab == t ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tab == t ? Color.accentColor : Color.gray.opacity(0.4)))
        .cornerRadius(8)
        .foregroundColor(tab == t ? .accentColor : .primary)
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
                let d = try await APIClient.shared.fetchMails()
                DispatchQueue.main.async {
                    list = d.items ?? []
                    availCount = d.available_count ?? 0
                    usedCount = d.used_count ?? 0
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

    private func doSync() async {
        syncing = true
        do {
            let d = try await APIClient.shared.syncMails()
            DispatchQueue.main.async {
                syncing = false
                toast = "同步完成：上游 \(d.total ?? 0)，本地 \(d.db_count ?? 0)，新增 \(d.new_items ?? 0)"
                load()
            }
        } catch {
            DispatchQueue.main.async {
                syncing = false
                toast = error.localizedDescription
            }
        }
    }

    private func doMarkUsed(_ email: String) async {
        do {
            _ = try await APIClient.shared.markUsed(email)
            DispatchQueue.main.async { toast = "已标记"; load() }
        } catch {
            DispatchQueue.main.async { toast = error.localizedDescription }
        }
    }

    private func receive(_ email: String) {
        receiving = email
        Task {
            do {
                let r = try await APIClient.shared.receive(email)
                DispatchQueue.main.async {
                    receiving = ""
                    if r.code != "00000" {
                        toast = r.msg ?? r.error ?? "收件失败"
                        return
                    }
                    let items = r.data ?? []
                    if items.isEmpty {
                        toast = "暂无邮件，稍后再试"
                        return
                    }
                    receiveResult = PresentableResult(
                        title: email,
                        lines: items.map { (time: $0.received_at ?? "", code: $0.code_match ?? "") }
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    receiving = ""
                    toast = error.localizedDescription
                }
            }
        }
    }
}