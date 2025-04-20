//
//  LightColorControlView.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/21/25.
//

import SwiftUI
import RealityKit

struct LightColorControlView: View {
    
    @Environment(AppModel.self) private var appModel
    
    @State private var color  = Color.black
    @State private var brightness: Double = 0.5
    @State private var isLightOn: Bool = false
    
    @State var hueControlManager = HueControlManager.shared
    @State private var lastColorUpdate: Date = Date()
    
    
    var body: some View {
        VStack(alignment:.center, spacing: 20) {
            HStack() {
                Spacer()
                Button {
                    // close the ui
                    appModel.showLightControlUI = false
                    // Animate Opacity to 0
                    let opacityAction = FromToByAction<Float>(to: 0.0,
                                                              timing: .easeInOut,
                                                              isAdditive: false)
                    do {
                        let opacityAnimation = try AnimationResource
                            .makeActionAnimation(for: opacityAction,
                                                 duration: 0.5,
                                                 bindTarget: .opacity)
                        appModel.lightColorControlUI.playAnimation(opacityAnimation)
                    } catch {
                        print(error.localizedDescription)
                        
                    }
                } label: {
                    Image(systemName: "xmark")
                }
            }
            
            Toggle("Light On", isOn: $isLightOn)
                .labelsHidden()
                .tint(color)
                .scaleEffect(2)
                .padding()
            ColorWheel(color: $color)
                .clipShape(Circle())
                .frame(width: 300, height: 300)
                .padding()
            Slider(value: $brightness, in: 0...1)
                .frame(width: 300)
            
        }
        .frame(width: 350)
        .padding(.all, 30)
        .onAppear {
            appModel.onLightControlUIPresented = {
                getLightOrGroupStatusAndUpdateUI()
            }
        }
        .onChange(of: isLightOn) { oldValue, newValue in
            guard var component = appModel.currentlySelectedComponent else { return }
            component.isLightOn = newValue
            appModel.lightsInfoPersistenceManager.updateLightControlComponent(component)
            if component.type == .light {
                hueControlManager.controlLight(lightName: component.name, state: ["on": newValue]) { result in
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        print("Error: \(error)")
                    }
                }
            } else if component.type == .group {
                hueControlManager.controlGroup(groupName: component.name, action: ["on": newValue]) { result in
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        print("Error: \(error)")
                    }
                }
            }
        }
        .onChange(of: color) { oldValue, newValue in
            guard let component = appModel.currentlySelectedComponent else { return }
            
            // Convert the new color to hue, saturation, and brightness
            let uiColor = UIColor(newValue)
            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var bri: CGFloat = 0
            var alpha: CGFloat = 0
            uiColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            let scaledHue = Int(hue * 65535)
            let scaledSat = Int(sat * 254)
            let scaledBri = Int(bri * 254)
            
            
            
            // Throttle: only send control message if at least 0.25 seconds have passed
            let now = Date()
            if now.timeIntervalSince(lastColorUpdate) < 0.25 {
                return
            }
            appModel.lightsInfoPersistenceManager.updateLightControlComponent(component)
            lastColorUpdate = now
            
            // Send the control command based on component type
            if component.type == .light {
                hueControlManager.controlLight(lightName: component.name, state: ["hue": scaledHue, "sat": scaledSat, "bri": scaledBri]) { result in
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        print("Error: \(error)")
                    }
                }
            } else if component.type == .group {
                hueControlManager.controlGroup(groupName: component.name, action: ["hue": scaledHue, "sat": scaledSat, "bri": scaledBri]) { result in
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        print("Error: \(error)")
                    }
                }
            }
        }
        
        .onChange(of: brightness) { oldValue, newValue in
            guard let component = appModel.currentlySelectedComponent else { return }
            let briValue = Int(newValue * 254)
            appModel.lightsInfoPersistenceManager.updateLightControlComponent(component)
            if component.type == .light {
                hueControlManager.controlLight(lightName: component.name, state: ["bri": briValue]) { result in
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        print("Error: \(error)")
                    }
                }
            } else if component.type == .group {
                hueControlManager.controlGroup(groupName: component.name, action: ["bri": briValue]) { result in
                    switch result {
                    case .success:
                        break
                    case .failure(let error):
                        print("Error: \(error)")
                    }
                }
            }
        }
    }
    
    func getLightOrGroupStatusAndUpdateUI() {
        if self.appModel.showLightControlUI == true {
            guard let component = self.appModel.currentlySelectedComponent else { return }
            
            let updateStateFromResult: (Result<[String: Any], Error>) -> Void = { result in
                switch result {
                case .success(let dict):
                    print(dict)
                    guard let state = dict["state"] as? [String: Any] else {
                        print("No 'state' found in response.")
                        return
                    }
                    
                    if let on = state["on"] as? Bool {
                        isLightOn = on
                        print("Setting toggle to \(on)")
                    } else if let onInt = state["on"] as? Int {
                        isLightOn = onInt != 0
                        print("Setting toggle to \(onInt != 0)")
                    }
                    
                    if let bri = state["bri"] as? Int {
                        brightness = Double(bri) / 254.0
                        print("Setting brightness to \(bri)")
                    }
                    
                    if let hueVal = state["hue"] as? Int,
                       let satVal = state["sat"] as? Int,
                       let briVal = state["bri"] as? Int {
                        let hueFloat = CGFloat(hueVal) / 65535.0
                        let satFloat = CGFloat(satVal) / 254.0
                        let briFloat = CGFloat(briVal) / 254.0
                        color = Color(hue: hueFloat, saturation: satFloat, brightness: briFloat)
                        print("Setting H S V to \(hueVal), \(satVal), \(briVal)")
                    }
                case .failure(let error):
                    print("Error getting status: \(error)")
                }
            }
            
            if component.type == .light {
                hueControlManager.getLightStatus(lightName: component.name, completion: updateStateFromResult)
            } else if component.type == .group {
                hueControlManager.getGroupStatus(groupName: component.name, completion: updateStateFromResult)
            }
        }
    }
}

#Preview {
    LightColorControlView()
}
