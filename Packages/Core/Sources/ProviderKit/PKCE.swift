import Foundation
import CryptoKit

/// A PKCE pair (RFC 7636). The verifier stays with the app; only the challenge
/// travels to the browser, so intercepting the URL gains nothing.
public struct PKCEPair: Sendable, Hashable {
    public let verifier: String
    public let challenge: String

    /// `nil` when the system could not supply random bytes. Continuing silently
    /// is not acceptable: on failure the buffer stays zeroed and the verifier
    /// becomes predictable, which means PKCE stops protecting anything.
    public static func generate() -> PKCEPair? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        let verifier = base64URL(Data(bytes))
        let digest = Data(SHA256.hash(data: Data(verifier.utf8)))
        return PKCEPair(verifier: verifier, challenge: base64URL(digest))
    }

    /// base64url without padding: `+` and `/` are invalid in URL parameters, and
    /// the specification forbids `=`.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
