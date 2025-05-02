//
//  SlingShotGestureManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/25/25.
//

import RealityKit
import ARKit
import UIKit

@MainActor
@Observable
class SlingShotGestureManager {
    var appModel: AppModel
    let handTracking: HandTrackingProvider
    
    // Entities representing key points for the peace gesture.
    var indexFingerEntity: Entity = Entity()
    var middleFingerEntity: Entity = Entity()
    var midpointEntity: Entity = Entity()
    var projectileEntity: Entity = Entity()
    
    // Flags
    var isPeaceGestureTracked: Bool = false
    var didAddEntities: Bool = false
    
    init(appModel: AppModel, handTracking: HandTrackingProvider) {
        self.appModel = appModel
        self.handTracking = handTracking
        
        // Setup collision event handler.
        ProjectileCollisionSystem.onCollision = {
            print("System fired a collision event")
            self.resetEntities()
        }
    }
    
    func resetEntities() {
        removeEntitiesForFingersAndProjectile()
        setVisualForEntities(parent: appModel.contentRoot)
    }
    
    func setVisualForEntities(parent: Entity) {
        guard appModel.lightControlMode == .slingShot else { return }
        let sphereMesh = MeshResource.generateSphere(radius: 0.005)
        let projectileMesh = MeshResource.generateSphere(radius: 0.02)
        
        let predefinedColors: [(hue: Int, saturation: Int, brightness: Int)] = [
            (hue: 0, saturation: 254, brightness: 254),
            (hue: Int(30.0/360.0 * 65535), saturation: 254, brightness: 254),
            (hue: Int(60.0/360.0 * 65535), saturation: 254, brightness: 254),
            (hue: Int(120.0/360.0 * 65535), saturation: 254, brightness: 254),
            (hue: Int(180.0/360.0 * 65535), saturation: 254, brightness: 254),
            (hue: Int(240.0/360.0 * 65535), saturation: 254, brightness: 254),
            (hue: Int(270.0/360.0 * 65535), saturation: 254, brightness: 254),
            (hue: Int(300.0/360.0 * 65535), saturation: 254, brightness: 254)
        ]
        
        guard let selectedColor = predefinedColors.randomElement() else {
            fatalError("No predefined colors available")
        }
        
        var projectileComponent = ProjectileComponent()
        projectileComponent.hue = selectedColor.hue
        projectileComponent.saturation = selectedColor.saturation
        projectileComponent.brightness = selectedColor.brightness
        
        let blueMaterial = SimpleMaterial(color: .blue, isMetallic: false)
        
        var projectileMaterial = PhysicallyBasedMaterial()
        let hueNormalized = CGFloat(selectedColor.hue) / 65535.0
        let saturationNormalized = CGFloat(selectedColor.saturation) / 254.0
        let brightnessNormalized = CGFloat(selectedColor.brightness) / 254.0
        let selectedUIColor = UIColor(hue: hueNormalized, saturation: saturationNormalized, brightness: brightnessNormalized, alpha: 1.0)
        projectileMaterial.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: selectedUIColor)
        projectileMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: selectedUIColor)
        
        // Create blue sphere entities for finger tips.
        let blueSphereEntity1 = ModelEntity(mesh: sphereMesh, materials: [blueMaterial])
        let blueSphereEntity2 = ModelEntity(mesh: sphereMesh, materials: [blueMaterial])
        let blueSphereEntity3 = ModelEntity(mesh: sphereMesh, materials: [blueMaterial])
        
        // Create the projectile entity.
        let projectileEntity = ModelEntity(mesh: projectileMesh, materials: [projectileMaterial])
        var inputTargetComponent = InputTargetComponent()
        // only allow for indirect input so the slingshot hand wont manipulate the projectile
        inputTargetComponent.allowedInputTypes = [.indirect]
        projectileEntity.components[InputTargetComponent.self] = inputTargetComponent
        projectileEntity.components[CollisionComponent.self] = CollisionComponent(shapes: [.generateSphere(radius: 0.02)])
        var pb = PhysicsBodyComponent()
        pb.isAffectedByGravity = false
        pb.linearDamping = 0
        projectileEntity.components[PhysicsBodyComponent.self] = pb
        projectileEntity.components.set(projectileComponent)
        
        self.indexFingerEntity = blueSphereEntity1
        self.middleFingerEntity = blueSphereEntity2
        self.midpointEntity = blueSphereEntity3
        self.projectileEntity = projectileEntity
        
        parent.addChild(indexFingerEntity)
        parent.addChild(middleFingerEntity)
        parent.addChild(projectileEntity)
        parent.addChild(midpointEntity)
        didAddEntities = true
        
        ProjectileCollisionSystem.HasFoundProjectile = false
    }
    
    func removeEntitiesForFingersAndProjectile() {
        indexFingerEntity.removeFromParent()
        midpointEntity.removeFromParent()
        middleFingerEntity.removeFromParent()
        projectileEntity.removeFromParent()
        didAddEntities = false
    }
    
    /// Monitors hand tracking updates and detects a peace gesture.
    func monitorPeaceGesture() async {
        
        for await update in handTracking.anchorUpdates {
            guard appModel.lightControlMode == .slingShot else { continue }
            let anchor = update.anchor
            guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
                isPeaceGestureTracked = false
                continue
            }
            
            let indexJoint = skeleton.joint(.indexFingerTip)
            let middleJoint = skeleton.joint(.middleFingerTip)
            let ringJoint = skeleton.joint(.ringFingerTip)
            let littleJoint = skeleton.joint(.littleFingerTip)
            let wristJoint = skeleton.joint(.wrist)
            
            guard indexJoint.isTracked,
                  middleJoint.isTracked,
                  ringJoint.isTracked,
                  littleJoint.isTracked,
                  wristJoint.isTracked
            else {
                isPeaceGestureTracked = false
                continue
            }
            
            let indexPosition = matrix_multiply(anchor.originFromAnchorTransform, indexJoint.anchorFromJointTransform).columns.3.xyz
            let middlePosition = matrix_multiply(anchor.originFromAnchorTransform, middleJoint.anchorFromJointTransform).columns.3.xyz

            let ringPosition = matrix_multiply(anchor.originFromAnchorTransform, ringJoint.anchorFromJointTransform).columns.3.xyz
            let littlePosition = matrix_multiply(anchor.originFromAnchorTransform, littleJoint.anchorFromJointTransform).columns.3.xyz
            let wristPosition = matrix_multiply(anchor.originFromAnchorTransform, wristJoint.anchorFromJointTransform).columns.3.xyz
            
            let indexDistanceFromWrist = distance(wristPosition, indexPosition)
            let ringDistanceFromWrist = distance(wristPosition, ringPosition)
            let littleDistanceFromWrist = distance(wristPosition, littlePosition)
            
            let extensionRatioThreshold: Float = 0.7
            if ringDistanceFromWrist > indexDistanceFromWrist * extensionRatioThreshold ||
                littleDistanceFromWrist > indexDistanceFromWrist * extensionRatioThreshold {
                isPeaceGestureTracked = false
                continue
            }
            
            
            // Define a threshold for the separation distance between the index and middle finger tips.
            let peaceGestureThreshold: Float = 0.03
            
            let separationDistance = distance(indexPosition, middlePosition)
            if separationDistance > peaceGestureThreshold {
                let midPoint = (indexPosition + middlePosition) / 2
                indexFingerEntity.transform = Transform(translation: indexPosition)
                if let projectileComponent = projectileEntity.components[ProjectileComponent.self] {
                    if (!projectileComponent.hasBeenManipulated) {
                        projectileEntity.transform = Transform(translation: midPoint)
                    }
                }
                midpointEntity.transform = Transform(translation: midPoint)
                middleFingerEntity.transform = Transform(translation: middlePosition)
                
                isPeaceGestureTracked = true
                if !didAddEntities {
                    setVisualForEntities(parent: appModel.contentRoot)
                }
            } else {
                isPeaceGestureTracked = false
                removeEntitiesForFingersAndProjectile()
                didAddEntities = false
            }
        }
    }
}
