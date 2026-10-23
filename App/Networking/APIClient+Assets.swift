import Foundation

extension APIClient {
    static func uploadAsset(fileData: Data, fileName: String, mimeType: String) async throws -> UploadAssetOutput {
        let data = try await MatrixRuntime.shared.stageUpload(fileData, fileName: fileName, mimeType: mimeType)
        return try JSONDecoder.beeper.decode(UploadAssetOutput.self, from: data)
    }
}
