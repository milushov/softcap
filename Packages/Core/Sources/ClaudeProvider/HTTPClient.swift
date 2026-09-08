import Foundation
import ProviderKit

/// The minimum a provider needs from the network. A separate protocol so that
/// tests never reach the internet.
public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int)
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> (Data, Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        try await send(url, method: "GET", headers: headers, body: nil)
    }

    public func post(
        _ url: URL, headers: [String: String], body: Data
    ) async throws -> (Data, Int) {
        try await send(url, method: "POST", headers: headers, body: body)
    }

    private func send(
        _ url: URL, method: String, headers: [String: String], body: Data?
    ) async throws -> (Data, Int) {
        // 30 s, matching the client this app borrows its identity from.
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, code)
        } catch {
            // The error is carried through rather than replaced by a fixed
            // phrase: "network unreachable" was reported for every failure a
            // request can have — a cancelled task, a TLS refusal, a timeout —
            // and none of them could be told apart. `URLError.Code` is a
            // number, not a message, and carries nothing about the user.
            let code = (error as? URLError)?.errorCode
            throw ProviderFailure(
                kind: .network,
                diagnostic: "request failed: \(code.map { "URLError \($0)" } ?? "\(type(of: error))")"
            )
        }
    }
}

/// Fetching a file, with progress, to a place the caller keeps.
///
/// Separate from `HTTPClient` because no provider needs it, and declared in this
/// file because this is the one file in the project that builds a `URLRequest` —
/// a rule `NothingElseLeavesYourMac` holds, and the reason the list of hosts
/// beside it is worth reading.
///
/// `URLSession.download(from:)` would have been shorter and takes a bare URL: it
/// would have passed that check without ever naming a request, which is worse
/// than failing it.
public protocol FileDownloader: Sendable {
    /// Downloads `url` and hands back a file in the temporary directory.
    /// The caller owns it and is responsible for removing it.
    func download(
        _ url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}

public struct URLSessionFileDownloader: FileDownloader {
    /// The session is built per download, so what it is built from is the only
    /// seam a test has. It exists for one: answering with a status this cannot
    /// otherwise be given.
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration? = nil) {
        self.configuration = configuration ?? Self.bounded
    }

    /// `timeoutInterval` on the request is the gap between packets. The only
    /// bound on the whole transfer is this one, and its default is seven days —
    /// long enough for a connection dribbling a packet a minute to hold a
    /// progress bar, and the screen behind it, until somebody relaunches the
    /// app. Half an hour is generous for a build of this size.
    private static var bounded: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 30 * 60
        return configuration
    }

    public func download(
        _ url: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        // A minute between packets, not a minute in total: a build is several
        // megabytes and `timeoutInterval` measures the gap, not the whole.
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "GET"

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(progress: progress, continuation: continuation)
            let session = URLSession(
                configuration: configuration, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: request).resume()
            // A session holds its delegate strongly until it is invalidated.
            // This lets the task finish and then lets both go.
            session.finishTasksAndInvalidate()
        }
    }
}

/// The delegate exists for one reason: `didWriteData` is the only place a
/// download says how far it has got, and the async API does not surface it.
///
/// `@unchecked Sendable` with a lock, because the callbacks arrive on the
/// session's own queue and the continuation must be resumed exactly once —
/// `didCompleteWithError` also fires after a download that succeeded.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?

    init(
        progress: @escaping @Sendable (Double) -> Void,
        continuation: CheckedContinuation<URL, any Error>
    ) {
        self.progress = progress
        self.continuation = continuation
    }

    private func finish(_ result: Result<URL, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // A download task calls this for any completed response, including one
        // that says no. Without this the body of a 404 was written to disk and
        // handed back as the file — whoever asked then found it did not match
        // what it should be, and said so in those words.
        // Only an HTTP answer has a status to read. A `file:` URL has none, and
        // treating its absence as a refusal turned every local read into a
        // failure — which is how this guard was first written.
        if let answer = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(answer.statusCode) {
            finish(.failure(ProviderFailure(
                kind: .network, diagnostic: "download came back \(answer.statusCode)")))
            return
        }

        // The system deletes `location` as soon as this returns, so the file is
        // moved before anything else is allowed to happen to it.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("softcap-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            progress(1)
            finish(.success(kept))
        } catch {
            finish(.failure(ProviderFailure(
                kind: .network, diagnostic: "the download could not be kept")))
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        // Success is reported by `didFinishDownloadingTo`, which has already
        // resumed the continuation; `finish` ignores a second call.
        guard let error else { return }
        let code = (error as? URLError)?.errorCode
        finish(.failure(ProviderFailure(
            kind: .network,
            diagnostic: "download failed: \(code.map { "URLError \($0)" } ?? "\(type(of: error))")"
        )))
    }
}
