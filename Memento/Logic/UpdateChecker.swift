import Foundation

/// Číselná verze („1.0.4“, ve tvaru tagu i „v1.0.4“). Chybějící složky se berou jako nula, tedy „1.0“ == „1.0.0“.
struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        var s = Substring(string)
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        guard !s.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in s.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(part), n >= 0 else { return nil }
            parsed.append(n)
        }
        components = parsed
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for i in 0..<max(lhs.components.count, rhs.components.count) {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Nejnovější zveřejněné vydání podle GitHubu.
struct ReleaseInfo: Equatable, Sendable {
    let version: AppVersion
    let tagName: String
    /// Stránka vydání, která se otevře v prohlížeči (je tam DMG ke stažení).
    let url: URL
}

/// Výsledek ruční kontroly: „aktuální“ a „selhalo“ se tu liší.
enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(ReleaseInfo)
    case upToDate
    case failed
}

/// Zeptá se GitHub Releases na novější verzi. `/releases/latest` nevrací koncepty ani předběžná vydání.
/// Každé selhání skončí „nic nového“ – kontrola aktualizací nesmí nikdy rušit chod aplikace.
struct UpdateChecker: Sendable {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/krausv/memento/releases/latest")!

    private let fetchData: @Sendable () async throws -> Data

    init(fetchData: @escaping @Sendable () async throws -> Data = UpdateChecker.fetchLatestRelease) {
        self.fetchData = fetchData
    }

    @Sendable static func fetchLatestRelease() async throws -> Data {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Dekóduje odpověď `/releases/latest`.
    static func decode(_ data: Data) throws -> ReleaseInfo {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let version = AppVersion(payload.tag_name), let url = URL(string: payload.html_url) else {
            throw URLError(.cannotParseResponse)
        }
        return ReleaseInfo(version: version, tagName: payload.tag_name, url: url)
    }

    func checkDetailed(currentVersion: String) async -> UpdateCheckResult {
        guard let current = AppVersion(currentVersion) else { return .failed }
        guard let data = try? await fetchData(), let release = try? Self.decode(data) else { return .failed }
        return release.version > current ? .updateAvailable(release) : .upToDate
    }

    /// Tichá podoba pro denní kontrolu na pozadí: novější vydání, jinak nil.
    func check(currentVersion: String) async -> ReleaseInfo? {
        if case .updateAvailable(let release) = await checkDetailed(currentVersion: currentVersion) { return release }
        return nil
    }
}
