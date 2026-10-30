import Foundation

nonisolated enum MatrixError: LocalizedError {
    case storeInUse, cannotStart, invalidRequest, invalidResponse, operationFailed
    /// The core's own message for a command that failed.
    case core(String)
    /// A command result that doesn't have the expected shape.
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .storeInUse: "These local messages are already open in another app process. Close that instance and retry."
        case .cannotStart: "Relay could not open its local message store. Your saved session has been preserved."
        case .invalidRequest: "The local request is invalid."
        case .invalidResponse: "The local message engine returned an invalid response."
        case .operationFailed: "The local Matrix operation could not complete. Try again when connected."
        case .core(let message):
            message.contains("context deadline exceeded") ? "The connection timed out. Please try again." : message
        case .decoding(let details): "Failed to decode Matrix core response: \(details)"
        }
    }
}
