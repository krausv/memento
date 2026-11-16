import Foundation

/// Odkaz na GitHub issue nebo pull request.
struct GitHubIssueRef: Equatable {
    let owner: String
    let repo: String
    let number: Int

    var url: String { "https://github.com/\(owner)/\(repo)/issues/\(number)" }
    /// `repo#123`
    var shortName: String { "\(repo)#\(number)" }

    /// Odkaz v poznámce: `[GH: Název (repo#123)](https://github.com/…)`.
    func markdownLink(title: String) -> String {
        let clean = title.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let escaped = clean
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[GH: \(escaped) (\(shortName))](\(url))"
    }
}

enum GitHubIssueLinks {
    /// Holá URL issue/PR, která ještě není v Markdown odkazu (`](` před ní).
    private static let bareURL = try! NSRegularExpression(
        pattern: #"(?<!\]\()https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(?:issues|pull)/(\d+)(?:[#?][^\s)]*)?"#
    )

    /// Nalezené holé URL a jejich rozsahy v textu.
    static func bareReferences(in text: String) -> [(ref: GitHubIssueRef, range: Range<String.Index>)] {
        let ns = text as NSString
        return bareURL.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard let range = Range(match.range, in: text),
                  let number = Int(ns.substring(with: match.range(at: 3))) else { return nil }
            let ref = GitHubIssueRef(
                owner: ns.substring(with: match.range(at: 1)),
                repo: ns.substring(with: match.range(at: 2)),
                number: number
            )
            return (ref, range)
        }
    }

    /// Nahradí holé URL odkazy s názvem. Co se nepodaří dohledat, zůstane beze změny.
    static func expand(_ text: String, resolver: GitHubIssueResolving) async -> String {
        let found = bareReferences(in: text)
        guard !found.isEmpty else { return text }
        var titles: [GitHubIssueRef: String] = [:]
        for ref in Set(found.map(\.ref)) {
            if let title = await resolver.title(for: ref), !title.isEmpty { titles[ref] = title }
        }
        var result = text
        for item in found.reversed() {
            guard let title = titles[item.ref] else { continue }
            result.replaceSubrange(item.range, with: item.ref.markdownLink(title: title))
        }
        return result
    }
}

extension GitHubIssueRef: Hashable {}

protocol GitHubIssueResolving {
    func title(for ref: GitHubIssueRef) async -> String?
}

/// Název dohledá přes nainstalované GitHub CLI (`gh api`), využívá jeho přihlášení.
struct GhCLIResolver: GitHubIssueResolving {
    var timeout: TimeInterval = 10

    static func locateGh() -> URL? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    func title(for ref: GitHubIssueRef) async -> String? {
        guard let gh = Self.locateGh() else { return nil }
        let timeout = timeout
        return await Task.detached { () -> String? in
            let process = Process()
            process.executableURL = gh
            process.arguments = ["api", "repos/\(ref.owner)/\(ref.repo)/issues/\(ref.number)", "--jq", ".title"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let title = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        }.value
    }
}

/// Zobrazení poznámek s Markdown odkazy (`[text](url)`) – jiný Markdown se záměrně neinterpretuje.
enum NoteText {
    private static let link = try! NSRegularExpression(pattern: #"\[((?:\\.|[^\]\\])*)\]\((https://[^)\s]+)\)"#)

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: #"\\(.)"#, with: "$1", options: .regularExpression)
    }

    /// Text bez odkazů – do PDF a krátkých souhrnů.
    static func plain(_ text: String?) -> String? {
        guard let text else { return nil }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in link.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += unescape(ns.substring(with: match.range(at: 1)))
            last = match.range.location + match.range.length
        }
        return result + ns.substring(from: last)
    }

    /// Text s klikatelnými odkazy.
    static func attributed(_ text: String) -> AttributedString {
        let ns = text as NSString
        var result = AttributedString()
        var last = 0
        for match in link.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += AttributedString(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            var part = AttributedString(unescape(ns.substring(with: match.range(at: 1))))
            part.link = URL(string: ns.substring(with: match.range(at: 2)))
            result += part
            last = match.range.location + match.range.length
        }
        return result + AttributedString(ns.substring(from: last))
    }
}

/// Doplnění názvů issue do uložené poznámky na pozadí.
@MainActor
enum NoteLinker {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.resolveGitHubIssues) as? Bool ?? true
    }

    /// Zavolat po uložení poznámky. Uložení nečeká na síť; poznámka se doplní, až název dorazí
    /// (jen pokud se mezitím nezměnila a záznam nezmizel).
    static func resolve(_ entry: TimeEntry, resolver: GitHubIssueResolving = GhCLIResolver()) {
        guard isEnabled, let original = entry.note,
              !GitHubIssueLinks.bareReferences(in: original).isEmpty else { return }
        Task {
            let expanded = await GitHubIssueLinks.expand(original, resolver: resolver)
            guard expanded != original, !entry.isDeleted, entry.note == original,
                  let context = entry.modelContext else { return }
            entry.note = expanded
            try? context.save()
        }
    }
}
