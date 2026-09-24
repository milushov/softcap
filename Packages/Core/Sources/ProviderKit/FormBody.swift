import Foundation

/// `application/x-www-form-urlencoded`, written once.
///
/// Two services exchange codes this way and they must encode identically —
/// a verifier or a device code that survives one encoder and not the other
/// fails as "the service rejected the code", which says nothing about the
/// character that did it. Keys are sorted so a test can read the result.
public enum FormBody {
    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    public static func encode(_ fields: [String: String]) -> Data {
        let text = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(escape(key))=\(escape(value))"
        }.joined(separator: "&")
        return Data(text.utf8)
    }

    /// Percent-encoding against the unreserved set rather than a URL component
    /// set: the latter leaves `+` alone, and a `+` in a form body is a space.
    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}
