//
//  ContentView.swift
//  LightControlTutorial
//
//  Created by Sarang Borude on 4/8/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    
    @Environment(AppModel.self) var appModel
    
    @State var hueBridgeDiscoverer = HueBridgeDiscoverer.shared // gets ip with an api call
    @State var hueBridgeUserManager = HueBridgeUserManager.shared // gets a username/token after pressing button on the bridge.
    @State var hueLocalDiscovery = HueLocalDiscovery.shared // gets ip with mdns
    @State var hueControlManager = HueControlManager.shared
    
    // State variables to trigger UI updates after fetching data
    @State private var isLightsLoaded = false
    @State var isGroupsLoaded = false
    @State private var errorMessage: String?
    
    var body: some View {
        
        
        VStack {
            HStack {
                Text("Philips Hue Control")
                    .font(.extraLargeTitle2)
                    .padding()
                Spacer()
                VStack(alignment: .leading) {
                    HStack {
                        Text("Hue Bridge IP: \(hueBridgeDiscoverer.firstBridge?.internalipaddress ?? "Not Found")")
                    }
                    HStack {
                        Text("Local Hue Bridge IP: \(hueLocalDiscovery.hueBridgeIP ?? "Not Found")")
                    }
                    
                    if(hueBridgeUserManager.isUsernameDiscovered){
                        HStack {
                            Text("Hue Bridge Username found")
                        }
                        .padding()
                    } else {
                        VStack {
                            Text("No username found, Press the button on hue bridge and press connect")
                            Button("Connect") {
                                hueBridgeUserManager.ensureAuthorized { result in
                                    switch result {
                                    case .success:
                                        print("Username retrieved successfully")
                                    case .failure(let error):
                                        print("Error: \(error)")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .padding(.horizontal, 100)
            
            if(hueBridgeUserManager.isUsernameDiscovered) {
                HStack(spacing: 50) {
                    Button("Load Lights") {
                        isLightsLoaded = true
                        hueControlManager.findLights { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success:
                                    print("Lights loading successful")
                                    isLightsLoaded = true
                                case .failure(let error):
                                    errorMessage = "Failed to load lights: \(error)"
                                    print("Failed to load lights: \(error)")
                                }
                            }
                        }
                    }
                    
                    Button("Load Groups") {
                        isGroupsLoaded = true
                        hueControlManager.findGroups { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success:
                                    print("group loading successful")
                                    isGroupsLoaded = true
                                    
                                case .failure(let error):
                                    print("group loading failed")
                                    errorMessage = "Failed to load groups: \(error)"
                                }
                            }
                        }
                    }
                }
                .frame(width: 600)
                .padding(.horizontal, 100)
            }
            
            // Show list of lights if loaded
            if isLightsLoaded {
                Text("Lights")
                    .font(.headline)
                
                ScrollView {
                    ForEach(Array(hueControlManager.lightNames.keys), id: \.self) { lightId in
                        let name = hueControlManager.lightNames[lightId] ?? "Unknown"
                        
                        HStack {
                            Text("Light \(lightId): \(name)")
                            Spacer()
                            Button("On") {
                                hueControlManager.controlLight(lightId: lightId, state: ["on": true]) { result in
                                    handleControlResult(result, itemName: name)
                                }
                            }
                            Button("Off") {
                                hueControlManager.controlLight(lightName: name, state: ["on": false]) { result in
                                    handleControlResult(result, itemName: name)
                                }
                            }
                        }
                        .frame(width: 500)
                    }
                }
                .padding()
            }
            
            // Show list of groups if loaded
            if isGroupsLoaded {
                Text("Groups")
                    .font(.headline)
                
                ScrollView {
                    ForEach(Array(hueControlManager.groupNames.keys), id: \.self) { groupId in
                        let name = hueControlManager.groupNames[groupId] ?? "Unknown"
                        
                        HStack {
                            Text("Group \(groupId): \(name)")
                            Spacer()
                            Button("On") {
                                hueControlManager.controlGroup(groupId: groupId, action: ["on": true]) { result in
                                    handleControlResult(result, itemName: name)
                                }
                            }
                            Button("Off") {
                                hueControlManager.controlGroup(groupName: name, action: ["on": false]) { result in
                                    handleControlResult(result, itemName: name)
                                }
                            }
                        }
                        .frame(width: 500)
                    }
                }
            }

//            Button("Clear Stored Bridge") {
//                hueBridgeUserManager.clearKeychain()
//            }
            
            ToggleImmersiveSpaceButton()
                .padding(.top, 100)
                .padding(.bottom, 100)
            
            VStack {
                HStack {
                    Text("Lights control mode : ")
                    Text(String(describing: appModel.lightControlMode))
                }
                HStack {
                    Button("Look And Pinch") {
                        appModel.changeLightControlMode(.lookAndPinch)
                    }
                    Button("Sling Shot") {
                        appModel.changeLightControlMode(.slingShot)
                    }
                }
            }
            
            if(appModel.immersiveSpaceState == .open) {
                // show content here for when immersive view is open.
                VStack {
                    Toggle(isOn: Binding( // you can create binding like this in a view!!!!
                        get: { appModel.isEditingLightSetup },
                        set: { appModel.isEditingLightSetup = $0 }))
                    {
                        Text ("Edit lighting setup")
                    }
                    .onChange(of: appModel.isEditingLightSetup, {
                        appModel.onLightEditingToggleChanged()
                    })
                    .frame(width: 200)
                    .padding(.vertical, 30)
                    
                    if appModel.isEditingLightSetup {
                        HStack {
                            Button("Add Light Control") {
                                appModel.addLightControl()
                            }
                            Button("Add Group Control") {
                                appModel.addGroupControl()
                            }
                            Button("Remove all controls") {
                                Task {
                                   await appModel.removeAllWorldAnchors()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
    
    /// Helper function to display success/failure in the UI
    private func handleControlResult(_ result: Result<Void, Error>, itemName: String) {
        DispatchQueue.main.async {
            switch result {
            case .success():
                errorMessage = "Successfully controlled: \(itemName)"
            case .failure(let error):
                errorMessage = "Control failed for \(itemName): \(error)"
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
