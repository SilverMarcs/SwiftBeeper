import Foundation

nonisolated enum MatrixError: LocalizedError {
    case storeInUse, cannotStart, invalidRequest, invalidResponse, operationFailed
    var errorDescription: String? {
        switch self {
        case .storeInUse: "These local messages are already open in another app process. Close that instance and retry."
        case .cannotStart: "Relay could not open its local message store. Your saved session has been preserved."
        case .invalidRequest: "The local request is invalid."
        case .invalidResponse: "The local message engine returned an invalid response."
        case .operationFailed: "The local Matrix operation could not complete. Try again when connected."
        }
    }
}
