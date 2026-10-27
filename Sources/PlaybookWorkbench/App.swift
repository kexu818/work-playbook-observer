import SwiftUI
import AppKit

struct Envelope<T: Decodable>: Decodable { let ok: Bool; let data: T?; let error: String? }
struct HistoryEvent: Decodable, Identifiable {
    let id, timestamp, app, kind, preview, source: String
    let line: Int
}
struct Summary: Decodable, Identifiable { let id, timestamp, title, level, source, text: String }
struct AppCount: Decodable, Identifiable { let name: String; let count: Int; var id: String { name } }
struct History: Decodable {
    let available: Bool
    let eventCount, summaryCount: Int
    let apps: [AppCount]; let events: [HistoryEvent]; let summaries: [Summary]
    let issues: [String]; let earliest, latest: String?; let root, memoryRoot, coverageNote: String
    let previewLimited: Bool
    let sourceMode: String
    let rawReadable: Bool
}
struct Feedback: Decodable { let at, status, note: String }
struct Candidate: Decodable, Identifiable {
    let id, title, problem, why, trigger, status: String
    let steps, checks, missing, sourceIds: [String]
    let feedback: [Feedback]
}
struct Evidence: Decodable, Identifiable {
    let id, type, at, text: String
    let app, kind, level: String?
}
struct WindowRange: Decodable { let start, end: String }
struct Coverage: Decodable {
    let totalEvents, includedEvents, totalSummaries, includedSummaries, textCharacters: Int
    let truncated: Bool
}
struct Analysis: Decodable, Identifiable {
    let id, createdAt, path, note: String
    let window: WindowRange; let coverage: Coverage
    let candidates: [Candidate]; let sources: [Evidence]
}
struct Analyses: Decodable { let analyses: [Analysis] }
struct Exported: Decodable { let path: String; let eventCount, summaryCount: Int }
struct Exports: Decodable { let exports: [Exported] }
struct Draft: Decodable { let title, markdown: String }

@MainActor final class Workbench: ObservableObject {
    @Published var history: History?
    @Published var analyses: [Analysis] = []
    @Published var presentations: [String: CandidatePresentation] = [:]
    @Published var exports: [Exported] = []
    @Published var hours = 24
    @Published var busy = false
    @Published var message = ""
    @Published var error = ""
    @Published var root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/2DC432GLL2.com.openai.sky.CUAService/Library/Caches/ComputerUse/Skysight").path
    @Published var memories = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/memories/extensions/skysight/resources").path
    var dataRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/work-playbook-observer").path
    var active: Process?
    var terminationObserver: NSObjectProtocol?
    var demo = false
    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--demo-root"), args.count > index + 1 {
            let folder = URL(fileURLWithPath: args[index + 1]); demo = true
            root = folder.appendingPathComponent("history").path
            memories = folder.appendingPathComponent("memories").path
            dataRoot = folder.appendingPathComponent("data").path
        } else if let bytes = try? Data(contentsOf: URL(fileURLWithPath: dataRoot).appendingPathComponent("sources.json")), let values = try? JSONDecoder().decode([String: String].self, from: bytes) {
            root = values["root"] ?? root; memories = values["memories"] ?? memories
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.active?.terminate() } }
    }
    var script: String {
        Bundle.main.resourceURL!.appendingPathComponent("history.py").path
    }
    func execute<T: Decodable>(_ command: String, extra: [String] = []) async throws -> T {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script, command, "--root", root, "--memories", memories, "--data", dataRoot, "--hours", String(hours)] + extra
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); active = process
        let bytes = await Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }.value
        process.waitUntilExit(); active = nil
        if process.terminationStatus == 130 { throw NSError(domain: "Workbench", code: 130, userInfo: [NSLocalizedDescriptionKey: "分析已取消"]) }
        let result = try JSONDecoder().decode(Envelope<T>.self, from: bytes)
        guard result.ok, let data = result.data else { throw NSError(domain: "Workbench", code: 1, userInfo: [NSLocalizedDescriptionKey: result.error ?? "读取未完成"]) }
        return data
    }
    func perform(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true; error = ""; message = ""
        Task { do { try await action() } catch { self.error = error.localizedDescription }; busy = false }
    }
    func refresh() {
        perform {
            if !self.demo {
                let folder = URL(fileURLWithPath: self.dataRoot)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let file = folder.appendingPathComponent("sources.json")
                try JSONEncoder().encode(["root": self.root, "memories": self.memories]).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            self.history = try await self.execute("status")
            let result: Analyses = try await self.execute("results"); self.analyses = result.analyses
            self.loadPresentations()
            let exported: Exports = try await self.execute("exports"); self.exports = exported.exports
        }
    }
    func loadPresentations() {
        presentations = [:]
        let file = URL(fileURLWithPath: dataRoot).appendingPathComponent("presentations.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let value = try JSONDecoder().decode(CandidatePresentationFile.self, from: Data(contentsOf: file))
            guard value.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
            for analysis in analyses {
                for candidate in analysis.candidates {
                    if let draft = value.candidates.first(where: {
                        $0.applies(to: candidate.id, title: candidate.title, sourceIDs: candidate.sourceIds,
                                   availableIDs: Set(analysis.sources.map(\.id)))
                    }) { presentations[candidate.id] = draft }
                }
            }
        } catch { message = "阅读样稿未能读取，已显示原始分析" }
    }
    func chooseSource(package: Bool = false) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.title = package ? "选择导出包文件夹" : "选择 Computer History 事件根目录"
        panel.message = package ? "选择包含 manifest.json 与 events.jsonl 的导出文件夹" : "选择含 segments 子目录的 Skysight 文件夹；应用只读访问。"
        panel.directoryURL = URL(fileURLWithPath: package ? dataRoot + "/exports" : root)
        if panel.runModal() == .OK, let url = panel.url { _ = url.startAccessingSecurityScopedResource(); root = url.path; refresh() }
    }
    func exportData() {
        perform {
            let result: Exported = try await self.execute("export"); self.exports.insert(result, at: 0)
            self.message = "已导出 \(result.eventCount) 条事件、\(result.summaryCount) 份摘要"
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.path)])
        }
    }
    func analyze() {
        perform {
            self.message = "正在使用 Codex 订阅分析，通常需要几分钟…"
            let record: Analysis = try await self.execute("analyze")
            self.analyses.insert(record, at: 0)
            self.message = record.candidates.isEmpty ? "分析完成：本次没有足够依据的候选" : "已生成 \(record.candidates.count) 个待核验候选"
        }
    }
    func cancel() { active?.terminate(); message = "正在取消并清理隔离会话…" }
    func saveDraft(_ id: String) {
        perform {
            let draft: Draft = try await self.execute("draft", extra: ["--candidate", id])
            let panel = NSSavePanel()
            panel.title = self.presentations[id] == nil ? "导出 Playbook 草稿" : "导出原始分析草稿"
            if self.presentations[id] != nil {
                panel.message = "文件包含原始模型分析，不包含当前阅读样稿的改写。导出不会改变候选状态。"
            }
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = draft.title.replacingOccurrences(of: "/", with: "-") + ".md"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try draft.markdown.write(to: url, atomically: true, encoding: .utf8)
                self.message = "已导出草稿：\(url.lastPathComponent)"
            }
        }
    }
    func feedback(_ id: String, status: String, note: String) {
        perform {
            let _: Candidate = try await self.execute("feedback", extra: ["--candidate", id, "--status", status, "--note", note])
            let result: Analyses = try await self.execute("results"); self.analyses = result.analyses
            self.message = "复用反馈已保存"
        }
    }
}

func localTime(_ text: String?) -> String {
    guard let text = text else { return "暂无" }
    let format = ISO8601DateFormatter(); format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = format.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    guard let date = date else { return text }
    return date.formatted(.dateTime.month().day().hour().minute())
}
