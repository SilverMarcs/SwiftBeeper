import Foundation

nonisolated struct MatrixRoomCommand: Encodable { let action = "opened-room"; let roomID: String }
