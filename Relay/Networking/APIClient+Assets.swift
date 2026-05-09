import Foundation

extension APIClient {
    static func uploadAsset(
        fileData: Data,
        fileName: String,
        mimeType: String,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> UploadAssetOutput {
        let url = APIConfiguration.baseURL.appending(path: "/v1/assets/upload")
        let boundary = UUID().uuidString

        var request = request(url: url, method: .post, accessToken: Self.accessToken)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n--\(boundary)--\r\n")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let (data, response) = try await URLSession.shared.upload(for: request, from: body, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, details: parseErrorMessage(from: data))
        }

        do {
            return try JSONDecoder.beeper.decode(UploadAssetOutput.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let onProgress: @MainActor @Sendable (Double) -> Void

    init(onProgress: @escaping @MainActor @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in
            onProgress(progress)
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
