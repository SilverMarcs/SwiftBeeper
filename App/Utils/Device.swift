//
//  Device.swift
//  Relay
//
//  Platform / idiom conveniences. Use these instead of scattering
//  `#if os(...)` and `UIDevice.current.userInterfaceIdiom` checks.
//

import SwiftUI

enum Device {
    static var isIPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    static var isIPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// True on macOS and iPad — i.e. the "large canvas" layouts that show the
    /// chat list and detail side-by-side and auto-select a chat.
    static var isMacOrPad: Bool {
        isMac || isIPad
    }
}

extension View {
    var isIPad: Bool { Device.isIPad }
    var isMac: Bool { Device.isMac }
    var isIPhone: Bool { Device.isIPhone }
    var isMacOrPad: Bool { Device.isMacOrPad }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
