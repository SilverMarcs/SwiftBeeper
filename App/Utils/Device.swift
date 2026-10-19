#if os(iOS)
import UIKit
#endif

enum Device {
    static var isIPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
}
