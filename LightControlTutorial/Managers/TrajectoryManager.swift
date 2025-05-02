//
//  TrajectoryManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/23/25.
//
import RealityKit
import simd
import SwiftUI

struct TrajectoryManager {
    
    @Environment(AppModel.self) var appModel
    // Parent entity that holds all the sphere entities for the trajectory.
    var trajectoryEntity: Entity = Entity()
    
    // Number of spheres along the curve.
    let sphereCount: Int = 10
    // Radius for each sphere.
    let sphereRadius: Float = 0.002

    // Generate a point on a quadratic bezier curve.
    func bezierPoint(t: Float, start: SIMD3<Float>, control: SIMD3<Float>, end: SIMD3<Float>) -> SIMD3<Float> {
        let u = 1 - t
        return u * u * start + 2 * u * t * control + t * t * end
    }
    
    // Create or update the spheres along the curve.
    mutating func updateTrajectory(start: SIMD3<Float>, control: SIMD3<Float>, end: SIMD3<Float>, rootEntity: Entity) {
        // Remove existing children if any.
        trajectoryEntity.children.removeAll()
        
        // Create spheres at calculated positions.
        for i in 0..<sphereCount {
            let t = Float(i) / Float(sphereCount - 1)
            let position = bezierPoint(t: t, start: start, control: control, end: end)
            let sphereMesh = MeshResource.generateSphere(radius: sphereRadius)
            var sphereMaterial = PhysicallyBasedMaterial()
            sphereMaterial.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: .white)
            let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
            sphereEntity.position = position
            let opacity = OpacityComponent(opacity: 1)
            sphereEntity.components.set(opacity)
            trajectoryEntity.addChild(sphereEntity)
        }
        
        // Add the trajectory entity to the scene if it's not already added.
        if trajectoryEntity.parent == nil {
            rootEntity.addChild(trajectoryEntity)
        }
    }
    
    // Hide or remove the trajectory.
    func clearTrajectory() {
        trajectoryEntity.children.removeAll()
        trajectoryEntity.removeFromParent()
    }
}
