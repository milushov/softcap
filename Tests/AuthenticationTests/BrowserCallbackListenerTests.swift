import Testing
import Foundation

@Suite @MainActor struct BrowserCallbackListenerTests {
    @Test func headerDeadlineDoesNotCancelADeferredSignInResponse() async throws {
        let listener = BrowserCallbackListener(headerTimeout: .milliseconds(100))
        let port = try await listener.start(port: nil) { _, connection in
            Task { @MainActor in
                // OAuth and persistence can outlive the header deadline.
                try? await Task.sleep(for: .milliseconds(300))
                let response = BrowserSignInPage.response(succeeded: true)
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        defer { listener.stop() }
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/callback"))
        let (body, response) = try await URLSession.shared.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self).contains("window.close()"))
    }
}
