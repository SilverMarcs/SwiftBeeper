import Foundation

nonisolated struct MatrixAssetCommand: Encodable { let action = "local-asset"; let url: String }
