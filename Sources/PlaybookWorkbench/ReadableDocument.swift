import SwiftUI

// A display projection only; the exact source remains available in the raw disclosure.
struct DocumentBlock: Identifiable {
    let id: Int
    let kind: Int // 0 paragraph, 1–6 heading, 7 list, 8 code
    let text: String
}

struct ReadableDocument: View {
    let text: String
    var blocks: [DocumentBlock] {
        var lines = text.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines = Array(lines.dropFirst(end + 1))
        }
        var result: [DocumentBlock] = [], paragraph: [String] = [], code: [String] = []
        var inCode = false
        func flush() {
            if !paragraph.isEmpty { result.append(DocumentBlock(id: result.count, kind: 0, text: paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                if inCode { result.append(DocumentBlock(id: result.count, kind: 8, text: code.joined(separator: "\n"))); code = [] }
                inCode.toggle(); continue
            }
            if inCode { code.append(line); continue }
            if trimmed.isEmpty { flush(); continue }
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); result.append(DocumentBlock(id: result.count, kind: hashes, text: String(trimmed.dropFirst(hashes + 1))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flush(); result.append(DocumentBlock(id: result.count, kind: 7, text: String(trimmed.dropFirst(2))))
            } else { paragraph.append(line) }
        }
        flush()
        if !code.isEmpty { result.append(DocumentBlock(id: result.count, kind: 8, text: code.joined(separator: "\n"))) }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(blocks) { block in
                if (1...6).contains(block.kind) {
                    Text(block.text).textSelection(.enabled).font(.system(size: block.kind <= 2 ? 16 : 13, weight: .semibold)).padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                } else if block.kind == 7 {
                    HStack(alignment: .top, spacing: 8) { Text("•").foregroundStyle(.tertiary); inline(block.text).textSelection(.enabled) }.font(.system(size: 12)).lineSpacing(5)
                } else if block.kind == 8 {
                    Text(block.text).textSelection(.enabled).font(.system(size: 11, design: .monospaced)).lineSpacing(4).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.inset, in: RoundedRectangle(cornerRadius: 6))
                } else { inline(block.text).textSelection(.enabled).font(.system(size: 12)).lineSpacing(6) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func inline(_ value: String) -> Text {
        // Preserve line breaks and native text selection without loading embedded media.
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
    }
}
