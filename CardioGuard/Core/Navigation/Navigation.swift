//
//  Navigation.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 20/05/2026.
//

import SwiftUI

enum AppScreen: Hashable {
    case scanner
    case dashboard
}

@MainActor @Observable
final class AppRouter {
    var path = NavigationPath()
    
    func navigate(to screen: AppScreen) {
        path.append(screen)
    }
    
    func navigateBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
    
    func popToRoot() {
        path = NavigationPath()
    }
}
