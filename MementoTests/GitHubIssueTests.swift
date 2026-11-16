import XCTest
@testable import Memento

final class GitHubIssueTests: XCTestCase {
    private struct Fake: GitHubIssueResolving {
        let titles: [Int: String]
        func title(for ref: GitHubIssueRef) async -> String? { titles[ref.number] }
    }

    private let url = "https://github.com/System-Digital/digi-sprava-webapp/issues/1656"

    func testFindsIssueAndPullURLsWithSuffix() {
        let text = "a \(url) b https://github.com/o/r/pull/7#issuecomment-1 c https://github.com/o/r/tree/main"
        let refs = GitHubIssueLinks.bareReferences(in: text).map(\.ref)
        XCTAssertEqual(refs, [
            GitHubIssueRef(owner: "System-Digital", repo: "digi-sprava-webapp", number: 1656),
            GitHubIssueRef(owner: "o", repo: "r", number: 7),
        ])
    }

    func testExpandReplacesURLWithLink() async {
        let result = await GitHubIssueLinks.expand("• \(url)", resolver: Fake(titles: [1656: "Oprava [login]"]))
        XCTAssertEqual(result, "• [GH: Oprava \\[login\\] (digi-sprava-webapp#1656)](\(url))")
    }

    func testExpandKeepsURLWhenTitleMissingAndSkipsExistingLinks() async {
        let linked = "[GH: X (r#1)](https://github.com/o/r/issues/1)"
        let text = "\(linked) a https://github.com/o/r/issues/2"
        let result = await GitHubIssueLinks.expand(text, resolver: Fake(titles: [1: "Jiný"]))
        XCTAssertEqual(result, text)
    }

    func testPlainStripsLinksAndUnescapes() {
        let note = "• [GH: Oprava \\[login\\] (r#1)](https://github.com/o/r/issues/1) hotovo *tučně*"
        XCTAssertEqual(NoteText.plain(note), "• GH: Oprava [login] (r#1) hotovo *tučně*")
        XCTAssertNil(NoteText.plain(nil))
    }

    func testAttributedHasLinkOnlyOnLabel() {
        let attr = NoteText.attributed("a [GH: T (r#1)](https://github.com/o/r/issues/1) b")
        XCTAssertEqual(String(attr.characters), "a GH: T (r#1) b")
        let linked = attr.runs.filter { $0.link != nil }
        XCTAssertEqual(linked.count, 1)
        XCTAssertEqual(linked.first?.link?.absoluteString, "https://github.com/o/r/issues/1")
    }
}
