//
//  LightControlComponent.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/17/25.
//

import RealityKit
import ARKit

// Ensure you register this component in your app’s delegate using:
// LightControlComponent.registerComponent()
public struct LightControlComponent: Component, Codable {
    // This is an example of adding a variable to the component.
    var type: LightControlType = .light
    //var id: String = "invalid"
    var name: String = "invalid"
    //var location: SIMD3<Float> = .zero
    var isLightOn = false // user should get this light state when app loads
    var worldAnchorID = UUID()

    public init() {

    }
}
