//
//  JustScanApp.swift
//  JustScan
//
//  Created by Justin Chow on 26/08/26.
//

import SwiftUI

@main
struct JustScanApp: App {
    private let container: AppContainer?
    private let launchError: Error?

    init() {
        do {
            // R-01-3: built once, here, and injected. Nothing else builds one.
            let modelContainer = try PersistenceController.container()
            let container = AppContainer(
                modelContainer: modelContainer,
                scanner: ScannerService()
            )
            #if DEBUG
            container.loadSeedIfNeeded()
            #endif
            self.container = container
            self.launchError = nil
        } catch {
            // A corrupt store is fatal and surfaced, never silently recreated —
            // recreating it would delete the operator's sales (01 §8).
            self.container = nil
            self.launchError = error
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootTabView()
                    .environment(container)
            } else {
                StoreUnavailableView(error: launchError)
            }
        }
    }
}
