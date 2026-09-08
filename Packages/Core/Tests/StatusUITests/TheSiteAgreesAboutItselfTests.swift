import Testing
import Foundation

/// The site says who and where it is many times over, and every copy agrees.
///
/// The address appears five times — `canonical`, `og:url`, the structured data,
/// the sitemap's `<loc>` and the line in `robots.txt` — plus a sixth as the
/// domain `deploy.sh` ships to. The name appears five times, the preview three,
/// the description twice. Nothing joined any of them.
///
/// A canonical pointing at an address the site no longer answers on is the kind
/// of mistake that costs whatever search traffic there was and shows no symptom
/// on the page itself. So the rule is not that these strings equal particular
/// values — they are free to change — but that changing one changes all.
@Suite struct TheSiteAgreesAboutItself {

    @Test func everyAddressSharesTheCanonicalOrigin() throws {
        let page = try Self.page()
        guard let canonical = Self.first(#"rel="canonical" href="([^"]+)""#, in: page),
              let origin = URL(string: canonical)?.host
        else { Issue.record("the page has no canonical address"); return }

        var stated: [(String, String)] = [
            ("og:url", Self.first(#"og:url" content="([^"]+)""#, in: page) ?? ""),
            ("structured data", Self.first(#""url":"([^"]+)""#, in: page) ?? ""),
            ("og:image", Self.first(#"og:image" content="([^"]+)""#, in: page) ?? ""),
            ("twitter:image", Self.first(#"twitter:image" content="([^"]+)""#, in: page) ?? ""),
        ]
        stated.append(("sitemap", Self.first(#"<loc>([^<]+)</loc>"#, in: try Self.file("sitemap.xml")) ?? ""))
        stated.append(("robots", Self.first(#"Sitemap: (\S+)"#, in: try Self.file("robots.txt")) ?? ""))

        for (where_, address) in stated {
            #expect(URL(string: address)?.host == origin, """
                \(where_) points at \(address), and the canonical origin is \(origin)
                """)
        }

        // And the place the deploy actually ships to.
        let deploy = try Self.file("deploy.sh")
        #expect(deploy.contains("SOFTCAP_DOMAIN:-\(origin)"), """
            deploy.sh ships to a different domain than the page calls canonical
            """)
    }

    @Test func everyNameIsTheSameName() throws {
        let page = try Self.page()
        guard let name = Self.first(#"og:site_name" content="([^"]+)""#, in: page)
        else { Issue.record("the page does not name itself"); return }

        for (where_, pattern) in [
            ("og:title", #"og:title" content="([^"]+)""#),
            ("twitter:title", #"twitter:title" content="([^"]+)""#),
            ("structured data", #""name":"([^"]+)""#),
        ] {
            #expect(Self.first(pattern, in: page) == name,
                    "\(where_) calls the site \(Self.first(pattern, in: page) ?? "nothing"), not \(name)")
        }
        let title = Self.first(#"<title>([^<]+)</title>"#, in: page) ?? ""
        #expect(title.hasPrefix(name), "the document title does not begin with \(name)")
    }

    @Test func theTwoDescriptionsAreOneDescription() throws {
        let page = try Self.page()
        let og = Self.first(#"og:description" content="([^"]+)""#, in: page)
        let twitter = Self.first(#"twitter:description" content="([^"]+)""#, in: page)
        #expect(og != nil && og == twitter,
                "the two shared-link descriptions have drifted apart")
    }

    // MARK: - reading

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let found = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[found])
    }

    private static func page() throws -> String { try file("index.html") }

    private static func file(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("site/\(name)"), encoding: .utf8)
    }

    private static var root: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}
