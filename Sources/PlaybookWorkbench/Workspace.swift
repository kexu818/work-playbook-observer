import SwiftUI
import AppKit

// Native semantic surfaces retain contrast in both macOS appearances.
enum Palette {
    static let accent = Color.accentColor
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let inset = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.09)
}

enum WorkspacePage: String, CaseIterable {
    case candidates, activity, exports
    var title: String {
        switch self { case .candidates: return "发现 Playbook"; case .activity: return "工作记录"; case .exports: return "数据与导出" }
    }
    var icon: String {
        switch self { case .candidates: return "square.stack"; case .activity: return "clock"; case .exports: return "externaldrive" }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Workbench
    @State private var page = WorkspacePage.candidates
    @State private var columns = NavigationSplitViewVisibility.all
    var candidateCount: Int { model.analyses.reduce(0) { $0 + $1.candidates.count } }
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $page) {
                Section("工作空间") {
                    ForEach(WorkspacePage.allCases, id: \.self) { item in
                        Label {
                            HStack {
                                Text(item.title)
                                Spacer()
                                if item == .candidates && candidateCount > 0 { Text("\(candidateCount)").foregroundStyle(.secondary).monospacedDigit() }
                            }
                        } icon: { Image(systemName: item.icon) }.tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Playbook")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Computer History", systemImage: "link").font(.caption.weight(.medium))
                    Text(model.history?.sourceMode == "export" ? "导出快照 · 只读" : model.history?.rawReadable == true ? "本机已连接 · 只读" : "等待连接本地数据")
                        .font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        } detail: {
            Group {
                switch page {
                case .candidates: CandidatesView()
                case .activity: ActivityView()
                case .exports: ExportView()
                }
            }
            .navigationTitle(page.title)
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.demo {
                    Text("演示样本 · 非真实工作").font(.caption2.weight(.medium)).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity).padding(5).background(.orange.opacity(0.08))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.busy || !model.error.isEmpty || !model.message.isEmpty { operationStatus }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Menu {
                        Picker("新分析与导出的时间范围", selection: $model.hours) {
                            Text("最近 1 小时").tag(1); Text("最近 24 小时").tag(24)
                            Text("最近 48 小时").tag(48); Text("最近 7 天").tag(168)
                        }
                    } label: { Label("时间范围", systemImage: "clock") }
                        .help("新分析与导出：最近 \(model.hours) 小时").disabled(model.busy)
                    Button { model.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        .help("刷新本地数据").disabled(model.busy).keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .task { model.refresh() }
        .onChange(of: model.hours) { _, _ in model.refresh() }
    }
    var operationStatus: some View {
        HStack(spacing: 9) {
            if model.busy { ProgressView().controlSize(.mini) }
            else { Image(systemName: model.error.isEmpty ? "checkmark.circle" : "exclamationmark.triangle").foregroundStyle(model.error.isEmpty ? Color.secondary : .red) }
            Text(model.error.isEmpty ? (model.message.isEmpty ? "正在读取本地数据…" : model.message) : model.error)
                .font(.caption).textSelection(.enabled).lineLimit(3)
            Spacer()
            if model.busy { Button("取消") { model.cancel() }.controlSize(.small) }
            else { Button { model.error = ""; model.message = "" } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭提示") }
        }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }
}

struct SearchField: View {
    let prompt: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 12))
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).help("清空搜索") }
        }.padding(9).background(Palette.inset, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct StatusBadge: View {
    let status: String
    var text: String { ["draft": "待核验", "effective": "反馈有效", "partial": "部分有效", "ineffective": "反馈无效"][status] ?? status }
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium))
            .foregroundStyle(status == "draft" ? Color.secondary : Palette.accent)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(status == "draft" ? Color.primary.opacity(0.05) : Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .help(status == "draft" ? "模型生成草稿，尚未验证" : "来自用户的复用反馈")
    }
}

struct EmptyWorkspace: View {
    let icon, title, detail: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(Palette.accent.opacity(0.7))
            Text(title).font(.system(size: 17, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4).frame(maxWidth: 330)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CandidateEntry: Identifiable {
    let analysis: Analysis
    let candidate: Candidate
    var id: String { candidate.id }
}

struct CandidatesView: View {
    @EnvironmentObject var model: Workbench
    @State private var selection: String?
    @State private var query = ""
    @State private var filter = "all"
    var entries: [CandidateEntry] { model.analyses.flatMap { a in a.candidates.map { CandidateEntry(analysis: a, candidate: $0) } } }
    var visible: [CandidateEntry] {
        entries.filter { entry in
            (filter == "all" || (filter == "draft" ? entry.candidate.status == "draft" : entry.candidate.status != "draft")) &&
            (query.isEmpty || (entry.candidate.title + entry.candidate.why + entry.candidate.trigger).localizedCaseInsensitiveContains(query))
        }
    }
    var current: CandidateEntry? { visible.first { $0.id == selection } }
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("所有候选").font(.headline)
                    Spacer()
                    Picker("候选状态", selection: $filter) {
                        Text("全部").tag("all"); Text("待核验").tag("draft"); Text("已反馈").tag("reviewed")
                    }.labelsHidden().fixedSize().controlSize(.small)
                }.padding(.horizontal, 18).padding(.vertical, 15)
                List(selection: $selection) {
                    ForEach(model.analyses) { analysis in
                        let items = visible.filter { $0.analysis.id == analysis.id }
                        if !items.isEmpty {
                            Section(localTime(analysis.createdAt)) {
                                ForEach(items) { entry in
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(entry.candidate.title).font(.system(size: 13, weight: .semibold)).lineSpacing(3).lineLimit(2)
                                        Text(entry.candidate.trigger).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3).lineLimit(2)
                                        HStack(spacing: 6) {
                                            Text(statusName(entry.candidate.status))
                                            Text("·")
                                            Text("\(entry.candidate.sourceIds.count) 条依据")
                                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                                    }.padding(.vertical, 8).frame(height: 112, alignment: .leading).tag(entry.id)
                                }
                            }
                        }
                    }
                }.listStyle(.inset).overlay {
                    if visible.isEmpty { Text(entries.isEmpty ? "分析后将在这里显示候选" : "没有匹配的候选").font(.caption).foregroundStyle(.secondary).padding(22) }
                }
                Text("\(visible.count) 个候选 · 尚需实际复用验证").font(.caption2).foregroundStyle(.secondary).padding(12)
            }.frame(minWidth: 250, idealWidth: 290, maxWidth: 330)
            Group {
                if let entry = current { CandidateDetail(analysis: entry.analysis, candidate: entry.candidate).id(entry.id) }
                else if entries.isEmpty {
                    VStack(spacing: 0) {
                        EmptyWorkspace(icon: "book.closed", title: "从工作记录中发现 Playbook", detail: "点击工具栏的“发现新候选”，分析已有记录。每个候选都会保留来源，供你核对。")
                        if let a = model.analyses.first { Text("最近分析：\(localTime(a.createdAt))\n\(a.note)").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24) }
                    }
                } else { EmptyWorkspace(icon: "line.3.horizontal.decrease", title: "没有匹配的候选", detail: "试试其他关键词，或切换候选状态。") }
            }.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $query, prompt: "搜索候选")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.analyze() } label: { Label("发现新候选", systemImage: "square.and.pencil") }
                    .help("使用 Codex 订阅，分析最近 \(model.hours) 小时的记录").disabled(model.busy || model.history?.available != true)
            }
        }
        .onChange(of: visible.map(\.id), initial: true) { _, ids in if !ids.contains(selection ?? "") { selection = ids.first } }
    }
}

func statusName(_ status: String) -> String {
    ["draft": "待核验", "effective": "反馈有效", "partial": "部分有效", "ineffective": "反馈无效"][status] ?? status
}

struct CandidateDetail: View {
    @EnvironmentObject var model: Workbench
    let analysis: Analysis
    let candidate: Candidate
    @State private var tab = "draft"
    @State private var note = ""
    @State private var feedbackStatus = "partial"
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(localTime(analysis.createdAt)).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Text(statusName(candidate.status)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(candidate.title).font(.system(size: 27, weight: .bold)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    if tab == "draft" { Text(candidate.why).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(6).fixedSize(horizontal: false, vertical: true) }
                }.id("candidate-top")
                if tab == "draft" { draft }
                else if tab == "evidence" { evidence }
                else { feedback }
            }.frame(maxWidth: 700, alignment: .leading).padding(.horizontal, 36).padding(.vertical, 25).frame(maxWidth: .infinity)
        }
        .onChange(of: tab) { _, _ in proxy.scrollTo("candidate-top", anchor: .top) }
        }
        .background(Palette.canvas)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("候选内容", selection: $tab) {
                    Text("草稿").tag("draft"); Text("依据 \(candidate.sourceIds.count)").tag("evidence"); Text("反馈").tag("feedback")
                }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { model.saveDraft(candidate.id) } label: { Label("导出草稿", systemImage: "square.and.arrow.up") }.disabled(model.busy)
            }
        }
        .onAppear { feedbackStatus = candidate.status == "draft" ? "partial" : candidate.status }
    }
    var draft: some View {
        VStack(alignment: .leading, spacing: 27) {
            VStack(alignment: .leading, spacing: 9) {
                Text("适用时机").font(.system(size: 14, weight: .semibold))
                Text(candidate.trigger).textSelection(.enabled).font(.system(size: 13)).lineSpacing(5)
            }.frame(maxWidth: .infinity, alignment: .leading)
            section("要解决的问题") { Text(candidate.problem).textSelection(.enabled).font(.system(size: 13)).lineSpacing(6) }
            section("操作步骤", aside: "\(candidate.steps.count) 步") {
                VStack(alignment: .leading, spacing: 19) {
                    ForEach(Array(candidate.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 13) {
                            Text(String(format: "%02d", i + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Palette.accent).padding(.top, 3).frame(width: 23)
                            Text(step).textSelection(.enabled).font(.system(size: 13)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            section("完成后检查") {
                VStack(alignment: .leading, spacing: 12) { ForEach(Array(candidate.checks.enumerated()), id: \.offset) { _, check in
                    Label { Text(check).textSelection(.enabled).lineSpacing(5) } icon: { Image(systemName: "checkmark").foregroundStyle(.secondary).font(.system(size: 10, weight: .semibold)) }.font(.system(size: 13))
                } }
            }
            if !candidate.missing.isEmpty {
                section("仍需你判断") { VStack(alignment: .leading, spacing: 10) { ForEach(Array(candidate.missing.enumerated()), id: \.offset) { _, item in Text("•  " + item).textSelection(.enabled).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5) } } }
            }
            Divider()
            HStack { Text("先核对依据，再在下一次工作中试用。").font(.system(size: 11)).foregroundStyle(.secondary); Spacer(); Button("核对来源 →") { tab = "evidence" }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent) }
        }
    }
    var evidence: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("本次分析的实际范围").font(.system(size: 12, weight: .semibold))
                Text("\(localTime(analysis.window.start)) — \(localTime(analysis.window.end))").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("使用 \(analysis.coverage.includedEvents)/\(analysis.coverage.totalEvents) 条事件、\(analysis.coverage.includedSummaries)/\(analysis.coverage.totalSummaries) 份摘要" + (analysis.coverage.truncated ? " · 内容已截取" : ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.inset, in: RoundedRectangle(cornerRadius: 8))
            ForEach(analysis.sources.filter { candidate.sourceIds.contains($0.id) }) { source in
                VStack(alignment: .leading, spacing: 11) {
                    HStack { Label(source.type == "summary" ? "工作摘要" : "原始事件", systemImage: source.type == "summary" ? "doc.text" : "cursorarrow").font(.system(size: 11, weight: .medium)); Spacer(); Text(localTime(source.at)).font(.system(size: 10)).foregroundStyle(.secondary) }
                    if let app = source.app { Text(app).font(.system(size: 11)).foregroundStyle(.secondary) }
                    ReadableDocument(text: source.text)
                    DisclosureGroup("查看原文") {
                        Text(source.text).font(.system(size: 11, design: .monospaced)).lineSpacing(4).textSelection(.enabled).padding(.top, 8)
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(source.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    Divider()
                }
            }
        }
    }
    var feedback: some View {
        VStack(alignment: .leading, spacing: 19) {
            Text("这份方法，在真实工作中有用吗？").font(.system(size: 17, weight: .semibold))
            Text("实际复用后记录结果。导出草稿本身不会改变有效状态。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
            Picker("复用结果", selection: $feedbackStatus) {
                Text("部分有效").tag("partial"); Text("已试用有效").tag("effective"); Text("无效").tag("ineffective"); Text("退回草稿").tag("draft")
            }.frame(maxWidth: 320, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text("发生了什么？哪些步骤需要调整？").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $note).font(.system(size: 13)).padding(9).frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line)).accessibilityLabel("复用反馈说明")
            }
            Button("保存反馈") { model.feedback(candidate.id, status: feedbackStatus, note: note); note = "" }
                .buttonStyle(.borderedProminent).disabled(model.busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !candidate.feedback.isEmpty {
                Divider(); Text("反馈记录").font(.system(size: 13, weight: .semibold))
                ForEach(Array(candidate.feedback.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 8) { HStack { StatusBadge(status: item.status); Text(localTime(item.at)).font(.system(size: 10)).foregroundStyle(.secondary) }; Text(item.note).font(.system(size: 12)).lineSpacing(5) }
                }
            }
        }
    }
    func section<Content: View>(_ title: String, aside: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(.system(size: 14, weight: .semibold)); Spacer(); Text(aside).font(.system(size: 10)).foregroundStyle(.tertiary) }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func shortDate(_ text: String) -> String { localTime(text).components(separatedBy: " ").first ?? localTime(text) }

struct ActivityView: View {
    @EnvironmentObject var model: Workbench
    @State private var selected: String?
    @State private var summaries = true
    @State private var query = ""
    var events: [HistoryEvent] { (model.history?.events ?? []).reversed().filter { query.isEmpty || ($0.app + $0.preview).localizedCaseInsensitiveContains(query) } }
    var records: [Summary] { (model.history?.summaries ?? []).reversed().filter { query.isEmpty || ($0.title + $0.text).localizedCaseInsensitiveContains(query) } }
    var ids: [String] { summaries ? records.map(\.id) : events.map(\.id) }
    var body: some View {
        if let history = model.history {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("工作记录").font(.system(size: 24, weight: .semibold))
                        Text("\(history.eventCount) 条事件 · \(history.summaryCount) 份摘要 · \(history.apps.count) 个应用").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.exportData() } label: { Label("导出原始数据", systemImage: "square.and.arrow.up") }.disabled(model.busy || !history.available)
                }.padding(24)
                Divider()
                HSplitView {
                    VStack(spacing: 13) {
                        Picker("记录类型", selection: $summaries) { Text("工作摘要").tag(true); Text("原始事件").tag(false) }.pickerStyle(.segmented).labelsHidden().controlSize(.small)
                        SearchField(prompt: summaries ? "搜索摘要" : "搜索应用或文本", text: $query)
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 3) {
                                    if summaries {
                                        ForEach(records) { summary in
                                            recordButton(summary.id, title: summary.title, subtitle: localTime(summary.timestamp), icon: "doc.text")
                                        }
                                    } else {
                                        ForEach(events) { event in
                                            recordButton(event.id, title: event.app, subtitle: "\(localTime(event.timestamp)) · \(eventLabel(event.kind))", icon: "cursorarrow")
                                        }
                                    }
                                    if ids.isEmpty { Text("没有匹配的记录").font(.caption).foregroundStyle(.secondary).padding(20) }
                                }
                            }.onChange(of: selected) { _, value in if let value { proxy.scrollTo(value) } }
                        }
                    }.padding(14).frame(minWidth: 240, idealWidth: 280, maxWidth: 330)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if summaries, let summary = records.first(where: { $0.id == selected }) {
                                Text("工作摘要 · \(localTime(summary.timestamp))").font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(summary.title).font(.system(size: 22, weight: .semibold)).lineSpacing(5)
                                ReadableDocument(text: summary.text)
                                DisclosureGroup("查看原始 Markdown") { Text(summary.text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).padding(.top, 8) }.font(.system(size: 10)).foregroundStyle(.secondary)
                            } else if !summaries, let event = events.first(where: { $0.id == selected }) {
                                Text("\(eventLabel(event.kind)) · \(localTime(event.timestamp))").font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(event.app).font(.system(size: 22, weight: .semibold))
                                Text(event.preview.isEmpty ? "这条事件没有可展示的文本" : event.preview).font(.system(size: 13)).lineSpacing(6).textSelection(.enabled)
                                Divider()
                                Text("文本预览最多 1600 字符，完整内容可通过原始导出查看。").font(.system(size: 11)).foregroundStyle(.secondary)
                                Text("\(event.source) · 第 \(event.line) 行").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled)
                            } else { EmptyWorkspace(icon: "doc.text.magnifyingglass", title: "没有匹配的记录", detail: "切换记录类型或调整搜索关键词。") }
                        }.frame(maxWidth: 680, alignment: .leading).padding(30).frame(maxWidth: .infinity, alignment: .top)
                    }.frame(minWidth: 400, maxWidth: .infinity)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("实际事件覆盖：\(localTime(history.earliest)) — \(localTime(history.latest))").font(.system(size: 10)).foregroundStyle(.secondary)
                    DisclosureGroup("覆盖范围与读取提示" + (history.issues.isEmpty ? "" : "（\(history.issues.count)）")) {
                        Text(history.coverageNote + (history.previewLimited ? " 界面预览最近 250 条，导出包含所选时段全部可读记录。" : "")).font(.caption).foregroundStyle(.secondary)
                        ForEach(history.issues, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }.onChange(of: ids, initial: true) { _, values in if !values.contains(selected ?? "") { selected = values.first } }
        } else { EmptyWorkspace(icon: "clock", title: "正在连接本地记录", detail: "读取 Computer History 已有数据，无需重新录屏。") }
    }
    func recordButton(_ id: String, title: String, subtitle: String, icon: String) -> some View {
        Button { selected = id } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(selected == id ? Palette.accent : Color.secondary).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected == id ? Palette.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
        }.buttonStyle(.plain).id(id)
    }
    func eventLabel(_ kind: String) -> String { ["window.changed": "切换窗口", "mouse.click": "点击", "keyboard.text_input": "输入文字", "keyboard.shortcut": "快捷键", "selection.changed": "选择内容", "mouse.drag": "拖动", "session.started": "观察开始"][kind] ?? kind }
}

struct ExportView: View {
    @EnvironmentObject var model: Workbench
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 9) { Text("数据与导出").font(.system(size: 25, weight: .semibold)); Text("本机保存，来源可核对。").font(.system(size: 12)).foregroundStyle(.secondary) }
                group("原始数据导出", icon: "square.and.arrow.up") {
                    Text("导出所选时段的原始事件、Markdown 摘要与文件校验清单。副本保存在本机，保留至你主动删除。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                    HStack { Button("导出所选时段") { model.exportData() }.buttonStyle(.borderedProminent).disabled(model.busy || model.history?.available != true); Button("打开数据目录") { NSWorkspace.shared.open(URL(fileURLWithPath: model.dataRoot)) } }
                    if !model.exports.isEmpty {
                        Divider()
                        ForEach(Array(model.exports.enumerated()), id: \.offset) { _, item in
                            HStack {
                                VStack(alignment: .leading, spacing: 6) { Text("\(item.eventCount) 条事件 · \(item.summaryCount) 份摘要").font(.system(size: 12, weight: .medium)); Text(URL(fileURLWithPath: item.path).lastPathComponent).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                                Spacer(); Button("在访达显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }.controlSize(.small)
                            }.padding(.vertical, 5)
                        }
                    }
                }
                group("数据源", icon: "link") {
                    Text("只读接入 Computer History 已生成的文件。").font(.system(size: 12)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) { Text("事件目录").font(.system(size: 11, weight: .medium)); TextField("事件根目录", text: $model.root).textFieldStyle(.roundedBorder).font(.system(size: 11)) }
                    VStack(alignment: .leading, spacing: 8) { Text("摘要目录").font(.system(size: 11, weight: .medium)); TextField("摘要 resources 目录", text: $model.memories).textFieldStyle(.roundedBorder).font(.system(size: 11)) }
                    HStack { Button("选择事件目录") { model.chooseSource() }; Button("打开导出包") { model.chooseSource(package: true) }; Button("重新读取") { model.refresh() } }.disabled(model.busy)
                }
                group("Codex 订阅", icon: "person.crop.circle") {
                    Text("使用本机 Codex 的 ChatGPT 登录，每次手动发起一轮分析。登录、额度或网络受限时会停止，无 API 计费回退。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5)
                }
            }.frame(maxWidth: 760, alignment: .leading).padding(34).frame(maxWidth: .infinity)
        }
    }
    func group<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).background(Palette.inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
    }
}

@main struct PlaybookWorkbenchApp: App {
    @StateObject private var model = Workbench()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).preferredColorScheme(previewScheme).frame(minWidth: 1000, minHeight: 660) }
            .defaultSize(width: 1240, height: 820).windowToolbarStyle(.unified)
    }
    // QA-only override keeps theme verification local to the demo window.
    var previewScheme: ColorScheme? {
        let args = CommandLine.arguments
        guard model.demo, let i = args.firstIndex(of: "--preview-appearance"), args.count > i + 1 else { return nil }
        return args[i + 1] == "dark" ? .dark : .light
    }
}
