//
//  Relay-Bridging-Header.h
//  Exposes the EasyMatrix Go backend's C ABI (built as EasyMatrix.xcframework
//  via Helpers/build-easymatrix-xcframework.sh) to Swift. The backend runs
//  in-process on both macOS and iOS — see EasyMatrixServer.swift.
//

#if !defined(REMOTE_ONLY)
#import "libeasymatrix.h"
#endif
