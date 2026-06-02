#if !os(macOS)
import Foundation
import Observation
import OSLog

// MARK: - C FFI function declarations using @_silgen_name

@_silgen_name("EasyMatrixCreate")
private func EasyMatrixCreate(_ cfgJSON: UnsafePointer<CChar>?) -> OpaquePointer?

@_silgen_name("EasyMatrixStart")
private func EasyMatrixStart(_ handle: OpaquePointer?) -> Int32

@_silgen_name("EasyMatrixStop")
private func EasyMatrixStop(_ handle: OpaquePointer?)

@_silgen_name("EasyMatrixDestroy")
private func EasyMatrixDestroy(_ handle: OpaquePointer?)

@_silgen_name("EasyMatrixHandleRequest")
private func EasyMatrixHandleRequest(_ handle: OpaquePointer?, _ reqJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("EasyMatrixRealtimeConnect")
private func EasyMatrixRealtimeConnect(_ handle: OpaquePointer?, _ callback: @convention(c) (Int, UnsafePointer<CChar>?) -> Void) -> Int

@_silgen_name("EasyMatrixRealtimeSend")
private func EasyMatrixRealtimeSend(_ handle: OpaquePointer?, _ realtimeHandle: Int, _ payloadJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("EasyMatrixRealtimeClose")
private func EasyMatrixRealtimeClose(_ handle: OpaquePointer?, _ realtimeHandle: Int)

@_silgen_name("EasyMatrixFreeCString")
private func EasyMatrixFreeCString(_ value: UnsafeMutablePointer<CChar>?)

@Observable
final class EasyMatrixFFI {
    static let shared = EasyMatrixFFI()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Relay", category: "EasyMatrixFFI")
    
    private var handle: OpaquePointer?
    private(set) var isStarted = false
    private var activeRealtimeHandle: Int?
    
    // For forwarding realtime callbacks to Swift
    static var realtimeCallback: ((String) -> Void)?
    
    private init() {}
    
    func start() async -> Bool {
        guard handle == nil else { return true }
        
        let stateDirURL = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "SwiftBeeper/gomuks")
        
        if let stateDirURL {
            try? FileManager.default.createDirectory(at: stateDirURL, withIntermediateDirectories: true)
        }
        
        let stateDirPath = stateDirURL?.path(percentEncoded: false) ?? ""
        
        // Define EasyMatrix in-process config
        let config: [String: Any] = [
            "stateDir": stateDirPath,
            "beeperHomeserverUrl": "https://matrix.beeper.com"
        ]
        
        guard let configData = try? JSONSerialization.data(withJSONObject: config),
              let configString = String(data: configData, encoding: .utf8) else {
            return false
        }
        
        logger.info("Initializing in-process EasyMatrix with stateDir: \(stateDirPath)")
        
        let handle = EasyMatrixCreate(configString)
        guard let handle else {
            logger.error("Failed to create EasyMatrix handle")
            return false
        }
        
        let startResult = EasyMatrixStart(handle)
        guard startResult == 0 else {
            logger.error("Failed to start EasyMatrix FFI runtime")
            EasyMatrixDestroy(handle)
            return false
        }
        
        self.handle = handle
        self.isStarted = true
        logger.info("EasyMatrix FFI runtime successfully started in-process")
        
        setupRealtimeBridge()
        
        return true
    }
    
    func stop() {
        guard let handle else { return }
        
        if let activeRealtimeHandle {
            EasyMatrixRealtimeClose(handle, activeRealtimeHandle)
        }
        
        EasyMatrixStop(handle)
        EasyMatrixDestroy(handle)
        self.handle = nil
        self.isStarted = false
        self.activeRealtimeHandle = nil
        EasyMatrixFFI.realtimeCallback = nil
    }
    
    // In-memory request handler that maps URLRequest to FFI call
    func handleRequest(_ request: URLRequest) async -> (Data, HTTPURLResponse)? {
        guard let handle, isStarted else { return nil }
        
        let method = request.httpMethod ?? "GET"
        var urlPath = request.url?.path ?? "/"
        if let query = request.url?.query {
            urlPath += "?\(query)"
        }
        
        // Build base64 body if present
        let bodyBase64 = request.httpBody?.base64EncodedString() ?? ""
        
        // Map headers
        var headers: [String: [String]] = [:]
        if let allHeaders = request.allHTTPHeaderFields {
            for (key, val) in allHeaders {
                headers[key] = [val]
            }
        }
        
        let requestDict: [String: Any] = [
            "method": method,
            "url": urlPath,
            "headers": headers,
            "body_base64": bodyBase64
        ]
        
        guard let requestData = try? JSONSerialization.data(withJSONObject: requestDict),
              let requestJSON = String(data: requestData, encoding: .utf8) else {
            return nil
        }
        
        // Execute CGo in-memory HTTP handle on a background thread to prevent blocking Swift cooperative thread pool
        let responseCString = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let res = EasyMatrixHandleRequest(handle, requestJSON)
                continuation.resume(returning: res)
            }
        }
        
        guard let responseCString else {
            return nil
        }
        
        defer {
            EasyMatrixFreeCString(responseCString)
        }
        
        let responseString = String(cString: responseCString)
        
        guard let responseData = responseString.data(using: .utf8),
              let responseDict = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return nil
        }
        
        if let error = responseDict["error"] as? String {
            if let requestURL = request.url,
               let httpResponse = HTTPURLResponse(
                   url: requestURL,
                   statusCode: 500,
                   httpVersion: "HTTP/1.1",
                   headerFields: [:]
               ) {
                return (error.data(using: .utf8) ?? Data(), httpResponse)
            }
        }
        
        let responsePayload = responseDict["response"] as? [String: Any] ?? [:]
        let status = responsePayload["status"] as? Int ?? 500
        let responseHeaders = responsePayload["headers"] as? [String: [String]] ?? [:]
        let respBodyB64 = responsePayload["body_base64"] as? String ?? ""
        
        let responseBody = Data(base64Encoded: respBodyB64) ?? Data()
        
        // Flatten headers for HTTPURLResponse
        var flattenedHeaders: [String: String] = [:]
        for (k, v) in responseHeaders {
            flattenedHeaders[k] = v.joined(separator: ", ")
        }
        
        if let requestURL = request.url,
           let httpResponse = HTTPURLResponse(
               url: requestURL,
               statusCode: status,
               httpVersion: "HTTP/1.1",
               headerFields: flattenedHeaders
           ) {
            return (responseBody, httpResponse)
        }
        
        return nil
    }
    
    // Realtime websocket streaming replacement
    private func setupRealtimeBridge() {
        guard let handle else { return }
        
        let callback: @convention(c) (Int, UnsafePointer<CChar>?) -> Void = { realtimeHandle, payloadCString in
            guard let payloadCString else { return }
            let payload = String(cString: payloadCString)
            
            // Forward event payload to Swift main actor
            Task { @MainActor in
                EasyMatrixFFI.realtimeCallback?(payload)
            }
        }
        
        let realtimeHandle = EasyMatrixRealtimeConnect(handle, callback)
        if realtimeHandle != 0 {
            self.activeRealtimeHandle = realtimeHandle
            logger.info("EasyMatrix Realtime FFI Bridge successfully connected (handle \(realtimeHandle))")
        } else {
            logger.error("Failed to connect EasyMatrix Realtime FFI Bridge")
        }
    }
    
    func sendRealtimeCommand(_ commandJSON: String) -> Bool {
        guard let handle, let activeRealtimeHandle else { return false }
        
        if let errorCString = EasyMatrixRealtimeSend(handle, activeRealtimeHandle, commandJSON) {
            let error = String(cString: errorCString)
            logger.error("FFI Realtime Send Error: \(error)")
            EasyMatrixFreeCString(errorCString)
            return false
        }
        return true
    }
}
#endif

