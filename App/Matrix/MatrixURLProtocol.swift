import Foundation
import Synchronization

/// Loads Matrix media from local files for the image library. The reserved
/// host is an identifier only; no socket or DNS request is made for it.
nonisolated final class MatrixURLProtocol: URLProtocol, @unchecked Sendable {
    private let loadingTask = Mutex<Task<Void, Never>?>(nil)

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == MatrixFiles.host
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = request
        let task = Task { @Sendable [weak self, request] in
            guard let self else { return }
            do {
                guard let url = request.url,
                      let source = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "url" })?.value else {
                    throw MatrixError.invalidRequest
                }
                let file = try await MatrixRuntime.shared.localAsset(source)
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Length": String(data.count)]) else {
                    throw MatrixError.invalidResponse
                }
                guard !Task.isCancelled else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard !Task.isCancelled else { return }
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
        loadingTask.withLock { $0 = task }
    }

    override func stopLoading() {
        loadingTask.withLock { task in task?.cancel(); task = nil }
    }
}
