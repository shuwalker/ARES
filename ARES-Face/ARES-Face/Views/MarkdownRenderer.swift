import SwiftUI

// MARK: - Markdown Renderer for Chat Messages
//
// Renders ARES responses with:
// - Code blocks (```...```) with syntax highlighting hint and copy button
// - Inline code (`...`) with background
// - Bold (**...**), italic (*...*)
// - Links [text](url)
// - Headers (### ...), (## ...), (# ...)
// - Bullet lists (- ... or * ...)
// - Numbered lists (1. ...)
// - Blockquotes (> ...)
// - Horizontal rules (---)
// - Tables (limited: header + rows, pipe-separated)

struct MarkdownRenderer {
    /// Parse markdown text into styled AttributedString blocks.
    /// Returns an array of "segments" — each is either a styled text block
    /// or a special element (code block, table, rule).
    static func render(_ markdown: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // skip closing ```
                segments.append(.codeBlock(lang: lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule
            if line.trimmingCharacters(in: .whitespaces) == "---" ||
                line.trimmingCharacters(in: .whitespaces) == "***" {
                segments.append(.horizontalRule)
                i += 1
                continue
            }

            // Table (pipe-separated with header)
            if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                var tableLines: [String] = []
                while i < lines.count && lines[i].contains("|") {
                    tableLines.append(lines[i])
                    i += 1
                }
                segments.append(.table(parseTable(tableLines)))
                continue
            }

            // Header
            if line.hasPrefix("### ") {
                segments.append(.header(level: 3, text: String(line.dropFirst(4))))
                i += 1
                continue
            }
            if line.hasPrefix("## ") {
                segments.append(.header(level: 2, text: String(line.dropFirst(3))))
                i += 1
                continue
            }
            if line.hasPrefix("# ") {
                segments.append(.header(level: 1, text: String(line.dropFirst(2))))
                i += 1
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].hasPrefix("> ") {
                    quoteLines.append(String(lines[i].dropFirst(2)))
                    i += 1
                }
                segments.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Unordered list
            let listMatch = line.prefix(2)
            if listMatch == "- " || listMatch == "* " {
                var items: [String] = []
                while i < lines.count {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                        items.append(String(trimmed.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                segments.append(.bulletList(items: items))
                continue
            }

            // Ordered list
            if let firstDigit = line.first, firstDigit.isNumber,
               line.contains(". ") {
                var items: [String] = []
                while i < lines.count {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if let d = trimmed.first, d.isNumber, trimmed.contains(". ") {
                        let dotIndex = trimmed.firstIndex(of: ".")!
                        items.append(String(trimmed[trimmed.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces))
                        i += 1
                    } else {
                        break
                    }
                }
                segments.append(.orderedList(items: items))
                continue
            }

            // Paragraph (aggregate consecutive non-empty lines)
            var paraLines: [String] = []
            while i < lines.count && !lines[i].isEmpty && !lines[i].hasPrefix("```") && !lines[i].hasPrefix("#") && !lines[i].hasPrefix("> ") && !lines[i].hasPrefix("- ") && !lines[i].hasPrefix("* ") && !lines[i].hasPrefix("---") {
                paraLines.append(lines[i])
                i += 1
                // Stop if next line is a block element
                if i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("```") || next.hasPrefix("#") || next.hasPrefix("> ") || next == "---" || next.hasPrefix("|") {
                        break
                    }
                }
            }
            if !paraLines.isEmpty {
                segments.append(.paragraph(text: paraLines.joined(separator: " ")))
            } else {
                i += 1 // skip empty line
            }
        }

        return segments
    }

    // MARK: - Inline Formatting
    /// Note: Inline formatting is handled by MarkdownSegmentView.parseInlineMarkdown()
    /// which uses Substring-based parsing for correctness with AttributedString.

    // MARK: - Table Parser

    private static func parseTable(_ lines: [String]) -> MarkdownTable {
        var rows: [[String]] = []
        for (i, line) in lines.enumerated() {
            // Skip separator row (|---|---|)
            if i == 1 && line.contains("---") { continue }
            let cells = line
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !cells.isEmpty { rows.append(cells) }
        }
        let headers = rows.first ?? []
        let body = rows.dropFirst().map { row in
            // Pad short rows
            var padded = row
            while padded.count < headers.count { padded.append("") }
            return padded
        }
        return MarkdownTable(headers: headers, rows: body)
    }
}

// MARK: - Segment Types

enum MarkdownSegment: Identifiable {
    case paragraph(text: String)
    case header(level: Int, text: String)
    case codeBlock(lang: String, code: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case blockquote(text: String)
    case horizontalRule
    case table(MarkdownTable)

    var id: String {
        switch self {
        case .paragraph(let t): return "p-\(t.prefix(20))"
        case .header(let l, let t): return "h\(l)-\(t.prefix(20))"
        case .codeBlock(let l, let c): return "code-\(l)-\(c.prefix(20))"
        case .bulletList(let items): return "ul-\(items.first ?? "")"
        case .orderedList(let items): return "ol-\(items.first ?? "")"
        case .blockquote(let t): return "bq-\(t.prefix(20))"
        case .horizontalRule: return "hr"
        case .table(let t): return "tbl-\(t.headers.first ?? "")"
        }
    }
}

struct MarkdownTable {
    let headers: [String]
    let rows: [[String]]
}

// MARK: - SwiftUI Rendering Views

struct MarkdownView: View {
    let markdown: String
    var fontSize: CGFloat = 13

    var body: some View {
        let segments = MarkdownRenderer.render(markdown)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments) { segment in
                MarkdownSegmentView(segment: segment, fontSize: fontSize)
            }
        }
    }
}

struct MarkdownSegmentView: View {
    let segment: MarkdownSegment
    let fontSize: CGFloat
    @State private var showCopyToast = false

    var body: some View {
        switch segment {
        case .paragraph(let text):
            inlineMarkdown(text)

        case .header(let level, let text):
            switch level {
            case 1:
                Text(text).font(.system(size: fontSize + 6, weight: .bold))
            case 2:
                Text(text).font(.system(size: fontSize + 3, weight: .semibold))
            default:
                Text(text).font(.system(size: fontSize + 1, weight: .semibold))
            }

        case .codeBlock(let lang, let code):
            VStack(alignment: .leading, spacing: 0) {
                // Header with language + copy button
                HStack {
                    if !lang.isEmpty {
                        Text(lang)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        showCopyToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopyToast = false
                        }
                    } label: {
                        Image(systemName: showCopyToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(showCopyToast ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))

                // Code content
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: fontSize - 1, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.85))
                        .textSelection(.enabled)
                        .padding(10)
                }
            }
            .background(Color.black.opacity(0.25))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.system(size: fontSize))
                            .foregroundStyle(.secondary)
                        inlineMarkdown(item)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                        inlineMarkdown(item)
                    }
                }
            }

        case .blockquote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.cyan.opacity(0.4))
                    .frame(width: 3)
                inlineMarkdown(text)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

        case .horizontalRule:
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .table(let table):
            MarkdownTableView(table: table, fontSize: fontSize)
        }
    }

    // MARK: - Inline Markdown

    /// Renders inline markdown (bold, italic, code, links) within a Text view.
    /// SwiftUI doesn't have great inline markdown support, so we do a
    /// simplified version that handles the most common patterns.
    @ViewBuilder
    private func inlineMarkdown(_ raw: String) -> some View {
        // Parse inline segments: **bold**, *italic*, `code`, [link](url)
        let attributed = parseInlineMarkdown(raw, fontSize: fontSize)
        Text(attributed)
    }

    private func parseInlineMarkdown(_ raw: String, fontSize: CGFloat) -> AttributedString {
        var result = AttributedString()
        result.font = .system(size: fontSize)

        var remaining = Substring(raw)

        while !remaining.isEmpty {
            // Code: `text`
            if let start = remaining.range(of: "`") {
                result.append(AttributedString(String(remaining[..<start.lowerBound])))
                let afterStart = remaining[start.upperBound...]
                if let end = afterStart.range(of: "`") {
                    var codeAttr = AttributedString(String(afterStart[..<end.lowerBound]))
                    codeAttr.font = .system(size: fontSize - 1, design: .monospaced)
                    codeAttr.backgroundColor = Color.white.opacity(0.08)
                    result.append(codeAttr)
                    remaining = afterStart[end.upperBound...]
                } else {
                    result.append(AttributedString(String(remaining)))
                    break
                }
            }
            // Bold: **text**
            else if let start = remaining.range(of: "**") {
                result.append(AttributedString(String(remaining[..<start.lowerBound])))
                let afterStart = remaining[start.upperBound...]
                if let end = afterStart.range(of: "**") {
                    var boldAttr = AttributedString(String(afterStart[..<end.lowerBound]))
                    boldAttr.font = .system(size: fontSize, weight: .bold)
                    result.append(boldAttr)
                    remaining = afterStart[end.upperBound...]
                } else {
                    result.append(AttributedString(String(remaining)))
                    break
                }
            }
            // Link pattern: [text](url)
            else if let linkStart = remaining.range(of: "[") {
                result.append(AttributedString(String(remaining[..<linkStart.lowerBound])))
                let afterBracket = remaining[linkStart.upperBound...]
                if let linkEnd = afterBracket.range(of: "](") {
                    let linkText = String(afterBracket[..<linkEnd.lowerBound])
                    let afterParen = afterBracket[linkEnd.upperBound...]
                    if let parenEnd = afterParen.range(of: ")") {
                        let url = String(afterParen[..<parenEnd.lowerBound])
                        var linkAttr = AttributedString(linkText)
                        linkAttr.font = .system(size: fontSize, weight: .medium)
                        linkAttr.foregroundColor = .cyan
                        linkAttr.underlineStyle = .single
                        linkAttr.link = URL(string: url)
                        result.append(linkAttr)
                        remaining = afterParen[parenEnd.upperBound...]
                    } else {
                        result.append(AttributedString(String(remaining)))
                        break
                    }
                } else {
                    result.append(AttributedString(String(remaining)))
                    break
                }
            }
            // Italic: *text* (single asterisk, not part of bold)
            else if let start = remaining.range(of: "*") {
                result.append(AttributedString(String(remaining[..<start.lowerBound])))
                let afterStart = remaining[start.upperBound...]
                if let end = afterStart.range(of: "*") {
                    var italicAttr = AttributedString(String(afterStart[..<end.lowerBound]))
                    italicAttr.font = .system(size: fontSize).italic()
                    result.append(italicAttr)
                    remaining = afterStart[end.upperBound...]
                } else {
                    result.append(AttributedString(String(remaining)))
                    break
                }
            }
            else {
                result.append(AttributedString(String(remaining)))
                break
            }
        }

        return result
    }
}

// MARK: - Table View

struct MarkdownTableView: View {
    let table: MarkdownTable
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                    Text(header)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
            }
            .background(Color.white.opacity(0.06))

            // Divider
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)

            // Data rows
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .font(.system(size: fontSize - 1))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                }
                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)
            }
        }
        .background(Color.black.opacity(0.15))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}