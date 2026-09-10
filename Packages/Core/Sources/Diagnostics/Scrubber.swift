import Foundation

/// What is removed from a report before it leaves the machine.
///
/// This is the load-bearing part of the module, not a courtesy. Softcap reads
/// the files two coding agents keep their credentials in, and the text that
/// describes a failure is assembled from whatever was at hand when it happened:
/// the path that would not parse, the account the refresh was for, the body the
/// server sent back. Any of those can carry a token, an address, or the name of
/// the person at the keyboard, and none of them looks dangerous in a diff.
///
/// So nothing is trusted to be clean. Every string on its way into an event
/// passes through here, and the rules below are written to over-redact: a report
/// missing a detail is a nuisance, a report carrying a refresh token is an
/// incident. `NothingElseLeavesYourMac` guards the other half of the same
/// promise — that the log never writes one of these in the clear.
public enum Scrubber {

    /// Each rule is a pattern and what replaces it. Order matters only where two
    /// could match the same run of text; the token rules come first so that a
    /// key which happens to contain an `@` is redacted as a key and not as an
    /// address.
    private static let rules: [(pattern: String, replacement: String)] = [
        // Anthropic and OpenAI issue keys with a fixed prefix and a long tail.
        // The prefix is the reliable part: the tail's alphabet has changed
        // before and would take the pattern with it.
        (#"sk-ant-[A-Za-z0-9_\-]+"#, "<token>"),
        (#"sk-[A-Za-z0-9]{16,}"#, "<token>"),

        // A JWT is three base64url runs joined by dots, and every OAuth token
        // this app touches is one. `eyJ` is `{"` encoded — the opening of the
        // header object, and the only part guaranteed to be there.
        (#"eyJ[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#, "<token>"),

        // A field named like a secret, whatever its value looks like. This
        // catches the shapes the rules above cannot know in advance — an opaque
        // refresh token is indistinguishable from a request id until something
        // beside it says what it is.
        //
        // The name is matched with its surrounding word characters rather than
        // on a word boundary: `\btoken\b` does not match inside `refresh_token`,
        // because an underscore is a word character and there is no boundary
        // between them. That is the exact name the credential files use, so the
        // boundary version redacted almost nothing that mattered.
        (#"(?i)[A-Za-z0-9_\-]*(token|secret|password|api[_\-]?key|authorization)[A-Za-z0-9_\-]*\s*[:=]\s*\S+"#,
         "<redacted>"),

        // A bearer credential is separated by a space, not by a colon, so it
        // needs its own rule; folding it into the one above would mean allowing
        // whitespace as a separator there, and "refresh token expired" would
        // come out as "<redacted> expired".
        (#"(?i)\bbearer\s+[A-Za-z0-9._\-]+"#, "<redacted>"),

        // The home directory names the person, and every path this app handles
        // begins with one. The rest of the path is the useful part and stays.
        (#"/Users/[^/\s"'\)\],]+"#, "/Users/<person>"),
        (#"/home/[^/\s"'\)\],]+"#, "/home/<person>"),

        // Addresses arrive from the account files: a report says which account
        // failed, and that identifier is an email more often than not.
        (#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "<email>"),
    ]

    private static let compiled: [(NSRegularExpression, String)] = rules.compactMap {
        guard let expression = try? NSRegularExpression(pattern: $0.pattern) else { return nil }
        return (expression, $0.replacement)
    }

    /// Applies every rule, in order.
    ///
    /// A pattern that fails to compile is dropped when `compiled` is built
    /// rather than here, so a broken rule cannot make this function return the
    /// text untouched — `redactionRulesAllCompile` fails the build instead.
    public static func clean(_ text: String) -> String {
        var result = text
        for (expression, replacement) in compiled {
            let whole = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result, range: whole, withTemplate: replacement)
        }
        return result
    }

    /// How many rules are in force. Used by the tests to refuse to pass
    /// vacuously if the table is ever emptied.
    public static var ruleCount: Int { compiled.count }
}
