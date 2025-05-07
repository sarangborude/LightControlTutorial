//
//  OrbsOnHandManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/25/25.
//

import RealityKit
import ARKit
import UIKit

@MainActor
@Observable
class OrbsOnHandGestureManager {
    var appModel: AppModel
    let handTracking: HandTrackingProvider
    
    // Holds the individual orb spheres.
    var orbSpheres: [ModelEntity] = []
    // An entity that acts as the container for the orb ring.
    var orbRingEntity: Entity = Entity()
    var animatedRingEntity: Entity = Entity()
    
    var isAnimating = false
    var isClosingRing = false
    
    // Predefined colors (same as projectile colors).
    let predefinedColors: [(hue: Int, saturation: Int, brightness: Int, uiHue: CGFloat)] = [
        (hue: 0, saturation: 254, brightness: 254, uiHue: 0.0),
        (hue: Int(30.0/360.0 * 65535), saturation: 254, brightness: 254, uiHue: 30.0/360.0),
        (hue: Int(60.0/360.0 * 65535), saturation: 254, brightness: 254, uiHue: 60.0/360.0),
        (hue: Int(120.0/360.0 * 65535), saturation: 254, brightness: 254, uiHue: 120.0/360.0),
        (hue: Int(180.0/360.0 * 65535), saturation: 254, brightness: 254, uiHue: 180.0/360.0),
        (hue: Int(240.0/360.0 * 65535), saturation: 254, brightness: 254, uiHue: 240.0/360.0),
        (hue: Int(270.0/360.0 * 65535), saturation: 254, brightness: 254, uiHue: 270.0/360.0),
        (hue: Int(300.0/360.0 * 65535), saturation: 254, brightness: 254, uiHue: 300.0/360.0)
    ]
    
    init(appModel: AppModel, handTracking: HandTrackingProvider) {
        self.appModel = appModel
        self.handTracking = handTracking
    }
    
    // Call this when a palm up gesture is detected to display the orb ring.
    func monitorPalmUpGesture() async {
        
        var palmUpStableCount = 0
        var palmDownStableCount = 0
        let requiredStableCount = 3
        
        for await update in handTracking.anchorUpdates {
            print("Hand tracking updates are coming in Orbs on hand gesture manager")
            guard appModel.lightControlMode == .orbsOnHand else { continue }
            let anchor = update.anchor
            guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
                continue
            }
            
            //
            guard anchor.chirality == .left else {
                continue
            }
            
            // Use the middleFingerMetacarpal joint as a proxy for the palm
            let palmJoint = skeleton.joint(.middleFingerMetacarpal)
            guard palmJoint.isTracked else {
                continue
            }
            
            // Compute the palm's transform and derive its up vector
            let palmTransform = matrix_multiply(anchor.originFromAnchorTransform, palmJoint.anchorFromJointTransform)
            let palmRotation = simd_quatf(palmTransform)
            let palmUpVector = palmRotation.act(SIMD3<Float>(0, 1, 0))
            
            // Define threshold for palm facing up
            let palmUpThreshold: Float = 0.5
            
            if palmUpVector.y > palmUpThreshold {
                palmUpStableCount += 1
                palmDownStableCount = 0
            } else {
                palmDownStableCount += 1
                palmUpStableCount = 0
            }
            
            if palmUpStableCount >= requiredStableCount {
                // Palm is facing up: show the orb ring with a spring animation
                
                if orbRingEntity.parent == nil {
                    orbRingEntity = Entity()
                    
                    //orbRingEntity.components.set(BillboardComponent()) // this doesn't work as expected.
                    
                    //An entity with BillboardComponent doesn’t provide access to its end orientation. Requesting the entity’s orientation through its transform returns only the unaltered orientation.
                    // https://developer.apple.com/documentation/realitykit/billboardcomponent
                    // that is why we use the look function for billboarding
                    
                    // Set initial scale small for animation effect
                    appModel.contentRoot.addChild(orbRingEntity)
                }
                
                // Position the orb ring slightly above the palm
                let palmPosition = palmTransform.columns.3.xyz
                let ringPosition = palmPosition + SIMD3<Float>(0, 0.2, 0)
                orbRingEntity.transform = Transform(translation: ringPosition)
                
                // Making the orb ring bilboard to the user manually.
                if(!isAnimating) {
                    // make the ring of orbs face the user.
                    let cameraTransform = appModel.getCurrentDeviceTransform()
                    if let cameraPos = cameraTransform?.translation {
                        orbRingEntity.look(at: cameraPos, from: orbRingEntity.position(relativeTo: nil), relativeTo: nil)
                    }
                }
                
                if animatedRingEntity.parent == nil {
                    animatedRingEntity = Entity()
                    // Set initial scale small for animation effect on the animated child
                    animatedRingEntity.scale = SIMD3<Float>(0.001, 0.001, 0.001)
                    animatedRingEntity.transform.rotation = simd_quatf(angle: Float.pi /  2 , axis: SIMD3<Float>(0, 0, 1))
                    orbRingEntity.addChild(animatedRingEntity)
                }
                
                // Create orb spheres if not already created
                if orbSpheres.isEmpty {
                    createOrbSpheres()
                    arrangeOrbSpheres(animated: false)
                }
                
                // Define target transform with full scale and rotation (360° around Y) for the animated child
                var targetTransform = animatedRingEntity.transform
                targetTransform.scale = SIMD3<Float>(1.0, 1.0, 1.0)
                let rotation = simd_quatf(angle: 0 , axis: SIMD3<Float>(0, 0, 1))
                targetTransform.rotation = rotation
                animatedRingEntity.move(to: targetTransform,
                                        relativeTo: animatedRingEntity.parent,
                                        duration: 1,
                                        timingFunction: .cubicBezier(controlPoint1: [0.34, 1.56], controlPoint2: [0.64, 1]))
                
            }
            if palmDownStableCount >= requiredStableCount && !isClosingRing {
                print("Closing orb ring")
                
                if orbRingEntity.parent != nil {
                    isAnimating = true
                    var targetTransform = animatedRingEntity.transform
                    targetTransform.scale = SIMD3<Float>(0.001, 0.001, 0.001)
                    isClosingRing = true
                    animatedRingEntity.move(to: targetTransform, relativeTo: animatedRingEntity.parent, duration: 0.5, timingFunction: .easeOut)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("orb ring closed")
                        self.isClosingRing = false
                        self.orbRingEntity.removeFromParent()
                        self.orbSpheres.removeAll()
                        self.isAnimating = false
                    }
                }
            }
        }
    }
    
    func createOrbSpheres() {
        let sphereMesh = MeshResource.generateSphere(radius: 0.02)
        orbSpheres = []
        for color in predefinedColors {
            var orbComponent = OrbComponent()
            orbComponent.hue = color.hue
            orbComponent.saturation = color.saturation
            orbComponent.brightness = color.brightness
            
            var orbMaterial = PhysicallyBasedMaterial()
            let hueNormalized = CGFloat(color.hue) / 65535.0
            let saturationNormalized = CGFloat(color.saturation) / 254.0
            let brightnessNormalized = CGFloat(color.brightness) / 254.0
            let selectedUIColor = UIColor(hue: hueNormalized, saturation: saturationNormalized, brightness: brightnessNormalized, alpha: 1.0)
            orbMaterial.emissiveColor = PhysicallyBasedMaterial.EmissiveColor(color: selectedUIColor)
            orbMaterial.baseColor = PhysicallyBasedMaterial.BaseColor(tint: selectedUIColor)
            orbMaterial.roughness = 0.0
            
            let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [orbMaterial])
            sphereEntity.components[InputTargetComponent.self] = InputTargetComponent()
            sphereEntity.components[CollisionComponent.self] = CollisionComponent(shapes: [.generateSphere(radius: 0.02)])
            sphereEntity.components[OrbComponent.self] = orbComponent
            
            orbSpheres.append(sphereEntity)
            
            animatedRingEntity.addChild(sphereEntity)
        }
    }
    
    func arrangeOrbSpheres(animated: Bool = true, emptySlotIndex: Int? = nil) {
        let sphereCount = orbSpheres.count
        // If an empty slot is to be left, total positions becomes count + 1; otherwise it's just the count
        let totalPositions = emptySlotIndex != nil ? sphereCount + 1 : sphereCount
        guard totalPositions > 0 else { return }
        let ringRadius: Float = 0.075
        var sphereIndex = 0
        for i in 0..<totalPositions {
            // If this index is meant to be empty, skip assigning a sphere
            if let emptyIndex = emptySlotIndex, i == emptyIndex {
                continue
            }
            let angle = (2 * Float.pi / Float(totalPositions)) * Float(i)
            let x = cos(angle) * ringRadius
            let y = sin(angle) * ringRadius
            let targetPosition = SIMD3<Float>(x, y, 0)
            let sphere = orbSpheres[sphereIndex]
            if animated {
                sphere.move(to: Transform(translation: targetPosition),
                            relativeTo: animatedRingEntity,
                            duration: 1,
                            timingFunction: .cubicBezier(controlPoint1: [0.34, 1.56], controlPoint2: [0.64, 1]))
            } else {
                sphere.transform = Transform(translation: targetPosition)
            }
            sphereIndex += 1
        }
    }
    
    // Called continuously while an orb is being dragged. newPosition is the current global position of the dragged orb.
    func updateDraggedOrb(_ draggedOrb: ModelEntity) {
        let ringCenter = orbRingEntity.position(relativeTo: nil)
        let newPosition = draggedOrb.position(relativeTo: nil)
        let distance = simd_distance(newPosition, ringCenter)
        let threshold: Float = 0.15
        
        // Convert newPosition to orbRingEntity's local coordinate space
        let localDraggedPosition = orbRingEntity.convert(position: newPosition, from: nil)
        let draggedAngle = atan2(localDraggedPosition.y, localDraggedPosition.x)
        let normalizedDraggedAngle = draggedAngle < 0 ? draggedAngle + 2 * Float.pi : draggedAngle
        print("sphere distance from ring: \(distance)")
        if distance > threshold {
            // If the orb is too far from the ring, ensure it is removed from the ring and from the animated child entity
            if let index = orbSpheres.firstIndex(of: draggedOrb) {
                orbSpheres.remove(at: index)
            }
            print("Arranging spheres for removal with no gap")
            // Arrange the remaining orbs with no empty slot
            arrangeOrbSpheres(animated: true)
        } else {
            print("Sphere is near the ring")
            // The orb is near the ring. Determine the insertion index based on the dragged angle by temporarily removing it from the array
            
            // Ensure the dragged orb is not part of orbSpheres during dragging so that its slot remains empty
            if let index = orbSpheres.firstIndex(of: draggedOrb) {
                orbSpheres.remove(at: index)
            }
            let insertionIndex = computeInsertionIndex(for: normalizedDraggedAngle, sphereCount: orbSpheres.count)
            
            print("Arranging spheres for insertion with empty slot at index \(insertionIndex)")
            
            // Animate the ring to adjust to the new ordering, leaving the empty slot at insertionIndex
            arrangeOrbSpheres(animated: true, emptySlotIndex: insertionIndex)
        }
    }
    
    // Called when a sphere is released near the ring; reinsert it into the ring.
    func onSphereReleased(_ sphere: ModelEntity) {
        let ringCenter = orbRingEntity.position(relativeTo: nil)
        let spherePosition = sphere.position(relativeTo: nil)
        let distance = simd_distance(spherePosition, ringCenter)
        let threshold: Float = 0.12 // meters
        
        if distance < threshold {
            let localPos = orbRingEntity.convert(position: spherePosition, from: nil)
            let angle = atan2(localPos.y, localPos.x)
            let normalizedAngle = angle < 0 ? angle + 2 * Float.pi : angle
            
            var remainingSpheres = orbSpheres
            if let index = remainingSpheres.firstIndex(of: sphere) {
                remainingSpheres.remove(at: index)
            }
            let insertionIndex = computeInsertionIndex(for: normalizedAngle, sphereCount: remainingSpheres.count)
            
            if orbSpheres.firstIndex(of: sphere) == nil {
                orbSpheres.insert(sphere, at: insertionIndex)
                animatedRingEntity.addChild(sphere, preservingWorldTransform: true)
                
            } else if let currentIndex = orbSpheres.firstIndex(of: sphere), currentIndex != insertionIndex {
                orbSpheres.remove(at: currentIndex)
                orbSpheres.insert(sphere, at: insertionIndex)
            }
            arrangeOrbSpheres(animated: true)
            if var orbComponent = sphere.components[OrbComponent.self] {
                orbComponent.hasBeenManipulated = false
                sphere.components[OrbComponent.self] = orbComponent
            }
        } else {
            // Optionally handle the case when the sphere is released far from the ring
        }
    }
    
    // Helper function to compute the insertion index for a dragged orb based on its angle.
    // sphereCount is the number of spheres currently in the ring excluding the dragged orb.
    func computeInsertionIndex(for draggedAngle: Float, sphereCount: Int) -> Int {
        guard sphereCount > 0 else { return 0 }
        
        // When the dragged orb is inserted, the total count will be sphereCount + 1
        let total = sphereCount + 1
        var idealAngles: [Float] = []
        for i in 0..<total {
            let angle = (2 * Float.pi / Float(total)) * Float(i)
            idealAngles.append(angle)
        }
        
        // Find the ideal angle that is closest to the dragged orb's angle
        var bestIndex = 0
        var smallestDiff = Float.greatestFiniteMagnitude
        for (i, angle) in idealAngles.enumerated() {
            let diff = abs(angle - draggedAngle)
            if diff < smallestDiff {
                smallestDiff = diff
                bestIndex = i
            }
        }
        return bestIndex
    }
    
    
    // Optionally, remove the orb ring from the scene.
    func removeOrbRing() {
        orbRingEntity.removeFromParent()
        orbSpheres.removeAll()
    }
    
}
