//
//  RunEnvironment.swift
//  CardioGuard
//
//  Explicit, injectable stand-in for "are we on a simulator or a real
//  device" - AppContainer takes this as a constructor parameter (defaulting
//  to `.current`) instead of branching on `#if targetEnvironment(simulator)`
//  inline at every call site, so the choice is overridable (e.g. for
//  previews or tests) rather than fixed at compile time per build target.
//

import Foundation

enum RunEnvironment {
    case simulated
    case live

    static var current: RunEnvironment {
        #if targetEnvironment(simulator)
        return .simulated
        #else
        return .live
        #endif
    }
}
