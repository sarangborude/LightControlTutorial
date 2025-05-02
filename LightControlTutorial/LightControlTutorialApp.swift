//
//  LightControlTutorialApp.swift
//  LightControlTutorial
//
//  Created by Sarang Borude on 4/12/25.
//

import SwiftUI

@main
struct LightControlTutorialApp: App {

    @State private var appModel = AppModel()
    
    init() {
        LightControlComponent.registerComponent()
        ProjectileComponent.registerComponent()
        ProjectileCollisionSystem.registerSystem()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
     }
}
