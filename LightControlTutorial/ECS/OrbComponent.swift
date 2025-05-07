//
//  ProjectileComponent.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/23/25.
//

import RealityKit
import ARKit
import SwiftUI

// Ensure you register this component in your app’s delegate using:
// OrbComponent.registerComponent()
public struct OrbComponent: Component, Codable {
    // This is an example of adding a variable to the component.
    
    public var hue: Int = 0
    public var saturation: Int = 0
    public var brightness: Int = 0
    public var hasBeenManipulated: Bool = false

    public init() {

    }
}
