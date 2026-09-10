import Foundation

/// Decoding only. Claims are display metadata and expiry hints, never proof of
/// identity: authentication is performed by the service over HTTPS.
public enum JWTClaims {
    public static func decode(_ value: String) -> [String: Any]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var body = parts[1].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while body.count % 4 != 0 { body += "=" }
        guard let data = Data(base64Encoded: body) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
