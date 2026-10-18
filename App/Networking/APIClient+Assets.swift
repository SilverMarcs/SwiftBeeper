import Foundation

extension APIClient {
    static func uploadAsset(
        fileData: Data,
        fileName: String,
        mimeType: String,
        onProgress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> UploadAssetOutput {
        onProgress(0)
        let data = try await MatrixRuntime.shared.stageUpload(fileData, fileName: fileName, mimeType: mimeType)
        onProgress(1)
        return try JSONDecoder.beeper.decode(UploadAssetOutput.self, from: data)
    }

}
