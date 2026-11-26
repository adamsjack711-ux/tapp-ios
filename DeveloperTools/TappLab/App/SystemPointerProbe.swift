#if !targetEnvironment(simulator)
#error("TappLab private diagnostics are simulator-only. Do not ship this target.")
#endif
import Darwin
import Foundation
import UIKit

enum SystemPointerProbe {
    /// Read-only C getters recovered from Apple's simulator binary imports.
    /// Missing symbols stay unknown; simulator values cannot certify a phone.
    static func read() -> [String: String] {
        var result = ["os": UIDevice.current.systemVersion, "environment": "iPhone simulator"]
        let paths = ["/usr/lib/libAccessibility.dylib",
                     "/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities"]
        let handles = paths.compactMap { dlopen($0, RTLD_LAZY | RTLD_LOCAL) }
        defer { handles.forEach { dlclose($0) } }
        let functions = [
            "AssistiveTouch": "_AXSAssistiveTouchEnabled",
            "Pointer Control": "_AXSPointerControlEnabled",
            "Dwell Control": "_AXSDwellControlEnabled",
            "Switch scanner": "_AXSAssistiveTouchScannerEnabled",
            "Pointer feature gate": "AXRuntimeCheck_AXAction_PointerControl"
        ]
        for (name, symbol) in functions {
            if let address = handles.lazy.compactMap({ dlsym($0, symbol) }).first {
                let getter = unsafeBitCast(address, to: (@convention(c) () -> Bool).self)
                result[name] = getter() ? "on" : "off"
            } else { result[name] = "unavailable" }
        }
        return result
    }
}
