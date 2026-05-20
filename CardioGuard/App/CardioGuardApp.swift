//
//  CardioGuardApp.swift
//  CardioGuard
//
//  Created by William Dias Dos Santos on 19/05/2026.
//

import SwiftUI

@main
struct CardioGuardApp: App {
    private let container = AppContainer.shared

    var body: some Scene {
        WindowGroup {
            DashBoardUIView()
                .environment(container.router)
        }
    }
}
