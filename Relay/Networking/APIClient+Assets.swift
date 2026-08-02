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

        let bodyFileURL = try makeMultipartBodyFile(
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyFileURL, delegate: delegate)

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

    private static func makeMultipartBodyFile(
        fileData: Data,
        fileName: String,
        mimeType: String,
        boundary: String
    ) throws -> URL {
        let bodyFileURL = FileManager.default.temporaryDirectory
            .appending(path: "relay-upload-\(UUID().uuidString).multipart")
        guard FileManager.default.createFile(atPath: bodyFileURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let handle = try FileHandle(forWritingTo: bodyFileURL)
        do {
            let safeFileName = fileName
                .replacing("\r", with: "_")
                .replacing("\n", with: "_")
                .replacing("\"", with: "_")
            try handle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try handle.write(contentsOf: Data(
                "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFileName)\"\r\n".utf8
            ))
            try handle.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
            try handle.write(contentsOf: fileData)
            try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try handle.close()
            return bodyFileURL
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: bodyFileURL)
            throw error
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
