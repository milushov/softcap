import Testing
import Foundation
import ProviderKit
@testable import ClaudeProvider

/// The downloader is not exercised against the network — no test in this
/// project reaches it. What is checked is the part that has been wrong before:
/// the file handed back is the caller's to keep, and it is not the one the
/// system deletes the moment the delegate returns.
///
/// `URLSession` serves `file:` URLs, so the real delegate path runs without a
/// server.
@Suite struct DownloadingAfile {

    @Test func afileIsServedFromDiskAndKept() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-download-\(UUID().uuidString).bin")
        try Data(repeating: 7, count: 64 * 1024).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let seen = Progress()
        let result = try await URLSessionFileDownloader().download(source) { seen.record($0) }
        defer { try? FileManager.default.removeItem(at: result) }

        #expect(FileManager.default.fileExists(atPath: result.path),
                "the file was gone by the time the caller saw it")
        #expect(try Data(contentsOf: result).count == 64 * 1024)
        #expect(result != source, "the caller was handed the very file it asked to copy")
        #expect(seen.last == 1, "progress never reached the end")
    }

    @Test func afileThatIsNotThereIsAnetworkFailure() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-not-here-\(UUID().uuidString).bin")
        await #expect(throws: ProviderFailure.self) {
            _ = try await URLSessionFileDownloader().download(missing) { _ in }
        }
    }

    /// The callback arrives on the session's own queue, so what it writes to
    /// has to survive being written to from there.
    private final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var fraction: Double?

        func record(_ value: Double) {
            lock.lock(); fraction = value; lock.unlock()
        }

        var last: Double? {
            lock.lock(); defer { lock.unlock() }
            return fraction
        }
    }
}

/// A download task hands back a file for any completed answer, including one
/// that says no.
///
/// Without a status check the body of a 404 was written to disk and handed on as
/// the archive. Whoever asked then hashed it, found it did not match what the
/// release published, and told the reader their download had been tampered with
/// — for a file the server had refused outright.
@Suite struct AnAnswerThatSaysNoIsNotAfile {

    private func url(saying status: Int) -> URL {
        URL(string: "https://example.invalid/\(status)/Softcap-0.1.47.zip")!
    }

    private var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Answering.self]
        return configuration
    }

    @Test func everyRefusalIsAnetworkFailure() async throws {
        for status in [400, 403, 404, 500, 503] {
            let error = await #expect(throws: ProviderFailure.self) {
                _ = try await URLSessionFileDownloader(configuration: configuration)
                    .download(url(saying: status)) { _ in }
            }
            #expect(error?.kind == .network, "a \(status) was handed back as a file")
            #expect(error?.diagnostic.contains("\(status)") == true,
                    "the log does not say which status came back")
        }
    }

    /// The other half, or the check above would pass by refusing everything.
    @Test func anAnswerThatSaysYesIsStillAfile() async throws {
        let file = try await URLSessionFileDownloader(configuration: configuration)
            .download(url(saying: 200)) { _ in }
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(try Data(contentsOf: file) == Data("body".utf8))
    }

    /// Answers with the status named in the path, and a body either way — which
    /// is the shape that made this a bug: an error page is bytes too.
    ///
    /// The status travels in the URL rather than in a stored property. It was a
    /// property first, and the suite runs in parallel: the test asking for 200
    /// was handed the 400 its neighbour had just set.
    private final class Answering: URLProtocol, @unchecked Sendable {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let asked = request.url?.pathComponents.compactMap(Int.init).first ?? 200
            let answer = HTTPURLResponse(
                url: request.url!, statusCode: asked,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: answer, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("body".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }
}
