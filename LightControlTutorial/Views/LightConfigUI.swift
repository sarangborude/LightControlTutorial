//
//  LightConfigUI.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/22/25.
//

import SwiftUI
import RealityKit

struct LightConfigUI: View {
    
    @Environment(AppModel.self) private var appModel
    @State var hueControlManager = HueControlManager.shared
    @State var selectedControlName = ""
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                
                // Delete (trash) button
                Button {
                    // Remove the selected light / group control
                    appModel.removeSelectedLightOrGroupControl()
                    
                    // Dismiss the configuration UI
                    appModel.showEditModeUI = false
                    
                    // Fade‑out animation
                    let opacityAction = FromToByAction<Float>(to: 0.0,
                                                              timing: .easeInOut,
                                                              isAdditive: false)
                    do {
                        let opacityAnimation = try AnimationResource
                            .makeActionAnimation(for: opacityAction,
                                                 duration: 0.5,
                                                 bindTarget: .opacity)
                        appModel.lightConfigUI.playAnimation(opacityAnimation)
                    } catch {
                        print(error.localizedDescription)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                
                // Close (xmark) button
                Button {
                    // Close the UI without deleting
                    appModel.showEditModeUI = false
                    
                    // Fade‑out animation
                    let opacityAction = FromToByAction<Float>(to: 0.0,
                                                              timing: .easeInOut,
                                                              isAdditive: false)
                    do {
                        let opacityAnimation = try AnimationResource
                            .makeActionAnimation(for: opacityAction,
                                                 duration: 0.5,
                                                 bindTarget: .opacity)
                        appModel.lightConfigUI.playAnimation(opacityAnimation)
                    } catch {
                        print(error.localizedDescription)
                    }
                } label: {
                    Image(systemName: "xmark")
                }
            }
            
            Text("Select light or group this sphere should control")
            HStack {
                Text("Type: \(appModel.currentlySelectedType)")
                Text("Name: \(selectedControlName)")
            }
            
            Picker("Select light or group", selection: $selectedControlName) {
                if(appModel.currentlySelectedType == .light) {
                    ForEach(Array(hueControlManager.lightNames.values), id: \.self) {
                        Text($0)
                    }
                } else if appModel.currentlySelectedType == .group {
                    ForEach(Array(hueControlManager.groupNames.values), id: \.self) {
                        Text($0)
                    }
                }
            }
            .pickerStyle(.wheel)
            .onChange(of: selectedControlName) { oldValue, newValue in
                appModel.currentlySelectedComponent!.name = newValue
                appModel.selectedLightControlEntity.components[LightControlComponent.self] = appModel.currentlySelectedComponent!
                appModel.lightsInfoPersistenceManager.updateLightControlComponent(appModel.currentlySelectedComponent!)
            }
            .onChange(of: appModel.showEditModeUI) { _, newValue in
                if(newValue == true) {
                    if(appModel.currentlySelectedType == .light) {
                        selectedControlName = hueControlManager.lightNames.values.first ?? ""
                    } else if appModel.currentlySelectedType == .group {
                        selectedControlName = hueControlManager.groupNames.values.first ?? ""
                    }
                }
            }
        }
        .frame(width: 350)
        .padding(.all, 30)
    }
}

#Preview {
    LightConfigUI()
}
