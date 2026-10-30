import Foundation

struct UploadAssetOutput: Decodable {
    let uploadID: String
    let width: Int?
    let height: Int?
}
