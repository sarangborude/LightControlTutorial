//
//  ImmersiveView.swift
//  LightControlTutorial
//
//  Created by Sarang Borude on 4/8/25.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct ImmersiveView: View {
    
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(AppModel.self) var appModel
    
    @State private var hueControlManager = HueControlManager.shared
    
    @State private var longPressStartTime: Date? = nil
    @State private var longPressTimerActive = false
    @State private var longPressTriggered = false
    
    @State private var slingShotMechanismManager = SlingShotMechanismManager()
    @State private var trajectoryManager = TrajectoryManager()
    
    var body: some View {
        RealityView { content, attachments in
            content.add(appModel.setupContentEntity())
            
            if let lightConfigUI = attachments.entity(for: "LightConfigUI") {
                lightConfigUI.components.set(OpacityComponent(opacity: 0))
                appModel.lightConfigUI = lightConfigUI
                content.add(lightConfigUI)
            }
            
            if let lightControlUI = attachments.entity(for: "LightColorControlUI") {
                lightControlUI.components.set(OpacityComponent(opacity: 0))
                appModel.lightColorControlUI = lightControlUI
                content.add(lightControlUI)
            }
        }
        update: { content, attachments in
            if(appModel.showEditModeUI) {
                positionUIEntityToFaceTheUserWithAnimation(entity: appModel.lightConfigUI)
            }
            
            if(appModel.showLightControlUI) {
                positionUIEntityToFaceTheUserWithAnimation(entity: appModel.lightColorControlUI)
            }
        } attachments: {
            Attachment(id: "LightConfigUI") {
                LightConfigUI()
                    .glassBackgroundEffect()
            }
            
            Attachment(id: "LightColorControlUI") {
                LightColorControlView()
                    .glassBackgroundEffect()
            }
        }
        .task {
            await appModel.runSession()
        }
        .task {
            await appModel.monitorSessionUpdates()
        }
        .task {
            await appModel.processWorldTrackingUpdates()
        }
        .task {
            //await appModel.handTrackingManager.monitorGestures()
            // we handle this is HandTrackingManager now to deal with mode changes.
        }
        .upperLimbVisibility(.hidden)
        .persistentSystemOverlays(.hidden)
        .gesture(SpatialTapGesture()
            .targetedToEntity(where: .has(LightControlComponent.self))
            .onEnded({ event in
                print("Tap gesture detected")
                appModel.currentlySelectedComponent = event.entity.components[LightControlComponent.self]
                appModel.selectedLightControlEntity = event.entity
                if(appModel.isEditingLightSetup) {
                    // show the light settings ui
                    appModel.currentlySelectedType = appModel.currentlySelectedComponent!.type
                    appModel.showEditModeUI = true
                }
                else {
                    // Handle Tap gesture when not in editing mode
                    handleTapGestureWhenNotEditing()
                }
            })
        )
        .gesture(
            DragGesture()
                .targetedToEntity(where: .has(LightControlComponent.self))
                .onChanged({ value in
                    if appModel.isEditingLightSetup {
                        value.entity.position = value.convert(value.location3D, from: .local, to: value.entity.parent!)
                    } else {
                        // trying to use this as a long press gesture
                        if longPressStartTime == nil {
                            longPressStartTime = Date()
                            longPressTimerActive = true
                        }
                        
                        if let startTime = longPressStartTime {
                            let duration = Date().timeIntervalSince(startTime)
                            if duration >= 0.25 && !longPressTriggered {
                                appModel.currentlySelectedComponent = value.entity.components[LightControlComponent.self]
                                appModel.selectedLightControlEntity = value.entity
                                handleLongTapGestureWhenNotEditing()
                                longPressTriggered = true
                            }
                        }
                    }
                })
                .onEnded({ value in
                    if appModel.isEditingLightSetup {
                        if let lcc = value.entity.components[LightControlComponent.self] {
                            Task {
                                await appModel.updateWorldAnchor(id: lcc.worldAnchorID, transform: value.entity.transformMatrix(relativeTo: nil))
                            }
                        }
                    } else {
                        longPressStartTime = nil
                        longPressTimerActive = false
                        longPressTriggered = false
                    }
                })
        )
        
        /// Long press gesture doesn't work reliably, the issue is also that you have to release it  so doesn't work great,
        /// we need something that activates when the user presses and holds
        //        .gesture(LongPressGesture(minimumDuration: 0.5)
        //            .targetedToEntity(where: .has(LightControlComponent.self))
        //            .onChanged({ event in
        //                print("long press on changed")
        //            })
        //                .onEnded { event in
        //                    print("This is a long press gesture")
        //                    appModel.currentlySelectedComponent = event.entity.components[LightControlComponent.self]
        //                    appModel.selectedLightControlEntity = event.entity
        //                    handleLongTapGestureWhenNotEditing()
        //                }
        //        )
        
        //Drag gesture handling for slingshot mechanism
        .gesture(DragGesture()
            .targetedToEntity(where: .has(ProjectileComponent.self))
            .onChanged({ value in
                
                // Update the current drag offset
                if let parent = value.entity.parent {
                    let currentPosition = value.convert(value.location3D, from: .local, to: parent)
                    let startPosition = appModel.handTrackingManager.slingShotGestureManager?.midpointEntity.position
                    
                    slingShotMechanismManager.updateDrag(to: currentPosition, newInitialPosition: startPosition)
                    
                    // Show trajectory when user is pulling back
                    let impulse = slingShotMechanismManager.computedImpulse()
                    let impulseDirection = normalize(impulse)
                    let start = currentPosition
                    let end = start + impulseDirection * 1.5 // change multiplier for longer prediction
                    
                    // Curve control point in the middle but raised for arc shape
                    var control = (start + end) / 2
                    control.y += 0.05
                    
                    trajectoryManager.updateTrajectory(start: start, control: control, end: end, rootEntity: parent)
                    
                    // Update the projectile's visual position to reflect the pull-back:
                    value.entity.position = (slingShotMechanismManager.initialDragPosition ?? currentPosition) + slingShotMechanismManager.currentDragOffset
                }
                
                if var pc = value.entity.components[ProjectileComponent.self] {
                    if pc.hasBeenManipulated {
                        return
                    }
                    pc.hasBeenManipulated = true
                    value.entity.components[ProjectileComponent.self] = pc
                }
            })
                .onEnded({ value in
                    
                    // remove the trajectory
                    trajectoryManager.clearTrajectory()
                    
                    // Compute the impulse from the slingshot pull
                    let impulse = slingShotMechanismManager.computedImpulse()
                    
                    // Retrieve and update the projectile's physics body to apply the force
                    if var physicsBody = value.entity.components[PhysicsBodyComponent.self] {
                        physicsBody.isAffectedByGravity = true
                        value.entity.components[PhysicsBodyComponent.self] = physicsBody
                        // Here, you would apply the impulse force. Depending on your implementation,
                        // you might use an applyImpulse method or manually update the entity's velocity.
                        // For example:
                        if let modelEntity = value.entity as? ModelEntity {
                            modelEntity.applyImpulse(impulse, at: modelEntity.position, relativeTo: nil)
                        }
                    }
                    
                    // Reset the entity after the collision..
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        appModel.handTrackingManager.slingShotGestureManager?.resetEntities()
                    }
                    
                    // Reset the slingshot manager for the next interaction
                    slingShotMechanismManager = SlingShotMechanismManager()
                })
        )
        
        //Drag gesture handling for orbs on hand
        .gesture(DragGesture()
            .targetedToEntity(where: .has(OrbComponent.self))
            .onChanged({ value in
                guard let parentEntity = value.entity.parent else { return }
                
                let newPosition = value.convert(value.location3D, from: .local, to: parentEntity)
                value.entity.position = newPosition
                appModel.handTrackingManager.orbsOnHandGestureManager?.updateDraggedOrb(value.entity as! ModelEntity)
                
                // change the parent of the orb to content root so it doesn't move with the ring.
                if var orbComponent = value.entity.components[OrbComponent.self] {
                    if orbComponent.hasBeenManipulated == false {
                        orbComponent.hasBeenManipulated = true
                        value.entity.components[OrbComponent.self] = orbComponent
                        value.entity.parent?.parent?.parent?.addChild(value.entity)
                        // entities parent is the animatedRingEnity, its parent is the orbRingEntity and it's parent is the content root
                    }
                }
            })
            .onEnded({ value in
                appModel.handTrackingManager.orbsOnHandGestureManager?.onSphereReleased(value.entity as! ModelEntity)
            })
        )
    }
    
    
    func handleTapGestureWhenNotEditing() {
        print("Trying to toggle light on or off")
        
        appModel.currentlySelectedComponent!.isLightOn.toggle()
        appModel.selectedLightControlEntity.components[LightControlComponent.self] = appModel.currentlySelectedComponent! // this assignment is really important
        print("Tap Gesture, Toggling light \(appModel.currentlySelectedComponent?.name ?? "Unknown") to \(appModel.currentlySelectedComponent?.isLightOn ?? false)")
        appModel.lightsInfoPersistenceManager.updateLightControlComponent(appModel.currentlySelectedComponent!)
        if(appModel.currentlySelectedComponent?.type == .light) {
            hueControlManager.controlLight(lightName: appModel.currentlySelectedComponent!.name, state: ["on": appModel.currentlySelectedComponent!.isLightOn]) { result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    print("Error: \(error)")
                }
            }
        } else if (appModel.currentlySelectedComponent?.type == .group) {
            hueControlManager.controlGroup(groupName: appModel.currentlySelectedComponent!.name, action: ["on": appModel.currentlySelectedComponent!.isLightOn]) { result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    print("Error: \(error)")
                }
            }
        }
    }
    
    private func handleLongTapGestureWhenNotEditing() {
        appModel.currentlySelectedType = appModel.currentlySelectedComponent!.type
        print("Long press gesture, showing UI for: \(appModel.currentlySelectedComponent?.name ?? "Unknown")")
        appModel.showLightControlUI = true
    }
    
    private func positionUIEntityToFaceTheUserWithAnimation(entity: Entity) {
        let showAction = FromToByAction<Float>(to: 1.0,
                                               timing: .easeOut,
                                               isAdditive: false)
        let hideAction = FromToByAction<Float>(to: 0.0,
                                               timing: .easeOut,
                                               isAdditive: false)
        
        do {
            let showAnimation = try AnimationResource
                .makeActionAnimation(for: showAction,
                                     duration: 0.25,
                                     bindTarget: .opacity)
            let hideAnimation = try AnimationResource
                .makeActionAnimation(for: hideAction,
                                     duration: 0.25,
                                     bindTarget: .opacity)
            
            // When the opacity is 1 that means the UI is visible on some other entity so we hide it first
            // then we show it
            let opacity = entity.components[OpacityComponent.self]?.opacity ?? 0
            
            if opacity == 1 {
                // entity is already visible, first hide
                entity.playAnimation(hideAnimation, transitionDuration: 0.0)
                
                // Delay position update until hide animation completes (assumed 0.25s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    appModel.onLightControlUIPresented?()
                    positionUIEntityToFaceUser(entity: entity)
                    entity.playAnimation(showAnimation)
                }
            } else {
                // Position then show
                appModel.onLightControlUIPresented?()
                positionUIEntityToFaceUser(entity: entity)
                entity.playAnimation(showAnimation)
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func positionUIEntityToFaceUser(entity: Entity) {
        if let deviceTransform = appModel.getCurrentDeviceTransform() {
            let userPosition = deviceTransform.translation
            let lightPosition = appModel.selectedLightControlEntity.position
            let direction = normalize(userPosition - lightPosition)
            let rightVector = normalize(cross([0, 1, 0], direction))
            let offset = rightVector * 0.3
            entity.position = lightPosition + offset
            let angle = atan2(direction.x, direction.z)
            entity.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
