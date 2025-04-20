//
//  AppModel.swift
//  LightControlTutorial
//
//  Created by Sarang Borude on 4/8/25.
//

import SwiftUI
import ARKit
import RealityKit

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    enum ErrorState: Equatable {
        case noError
        case providerNotSupported
        case providerNotAuthorized
        case sessionError(ARKitSession.Error)
        
        static func == (lhs: AppModel.ErrorState, rhs: AppModel.ErrorState) -> Bool {
            switch (lhs, rhs) {
            case (.noError, .noError): return true
            case (.providerNotSupported, .providerNotSupported): return true
            case (.providerNotAuthorized, .providerNotAuthorized): return true
            case (.sessionError(let lhsError), .sessionError(let rhsError)): return lhsError.code == rhsError.code
            default: return false
            }
        }
    }
    
    // When a person denies authorization or a data provider state changes to an error condition,
    // the main window displays an error message based on the `errorState`.
    var errorState: ErrorState = .noError
    
    private let session = ARKitSession()
    private let worldTracking = WorldTrackingProvider()
    
    let contentRoot = Entity()
    var lightConfigUI = Entity()
    var lightColorControlUI =  Entity()
    
    var showEditModeUI = false
    var showLightControlUI = false
    
    private var worldAnchors = [UUID: WorldAnchor]()
    private var lightEntities =  [UUID: Entity]()
    
    public var lightsInfoPersistenceManager = LightsInfoPersistenceManager.shared
    
    public var isEditingLightSetup: Bool = false
    
    var currentlySelectedComponent: LightControlComponent?
    var currentlySelectedType: LightControlType = .none
    var currentLightControlName: String!
    var selectedLightControlEntity = Entity()
    
    var onLightControlUIPresented: (()->Void)?
    
    init() {
        lightsInfoPersistenceManager.loadLightControlComponentsFromDisk()
        
        if !areAllDataProvidersSupported {
            errorState = .providerNotSupported
        }
        Task {
            if await !areAllDataProvidersAuthorized() {
                errorState = .providerNotAuthorized
            }
        }

        Task {
            do {
                await HueBridgeUserManager.shared.waitUntilUsernameDiscovered()
                try await Task.sleep(for: .seconds(5))
                print("Starting to find lights and groups")
                HueControlManager.shared.findLightsAndGroups { result in
                    switch result {
                    case .failure(let error):
                        print("Error finding lights: \(error)")
                    case .success(let (lights, groups)):
                        print("Found \(lights.count) lights")
                        print("Found \(groups.count) groups")
                    }
                }
            }
        }
    }
    
    /// Sets up the root entity in the scene.
    func setupContentEntity() -> Entity {
        return contentRoot
    }
    
    private var areAllDataProvidersSupported: Bool {
        return WorldTrackingProvider.isSupported
    }
    
    func areAllDataProvidersAuthorized() async -> Bool {
        // It's sufficient to check that the authorization status isn't 'denied'.
        // If it's `notdetermined`, ARKit presents a permission pop-up menu that appears as soon
        // as the session runs.
        let authorization = await ARKitSession().queryAuthorization(for: [.worldSensing])
        return authorization[.worldSensing] != .denied
    }
    
    /// Responds to events such as authorization revocation.
    func monitorSessionUpdates() async {
        for await event in session.events {
            print("\(event.description)")
            switch event {
            case .authorizationChanged(type: _, status: let status):
                print("Authorization changed to: \(status)")
                
                if status == .denied {
                    errorState = .providerNotAuthorized
                }
            case .dataProviderStateChanged(dataProviders: let providers, newState: let state, error: let error):
                print("Data providers state changed: \(providers), \(state)")
                if let error {
                    print("Data provider reached an error state: \(error)")
                    errorState = .sessionError(error)
                }
            @unknown default:
                fatalError("Unhandled new event type \(event)")
            }
        }
    }
    
    func runSession() async {
        do {
            try await session.run([worldTracking])
        } catch {
            guard error is ARKitSession.Error else {
                preconditionFailure("Unexpected error \(error).")
            }
            // Session errors are handled in AppState.monitorSessionUpdates().
        }
    }
    
    /// Updates the world tracking anchor as new data arrives from ARKit.
    func processWorldTrackingUpdates() async {
        for await update in worldTracking.anchorUpdates {
            let worldAnchor = update.anchor
            switch update.event {
            case .added:
                print(">>>>>> adding world anchor")
                
                let lcc = lightsInfoPersistenceManager.lightControlComponents.first {$0.worldAnchorID == worldAnchor.id}
                guard let lcc = lcc else {
                    print(">>>>>> no light control component when adding world anchor")
                    return
                }
                guard let lightControlEntity = await createLightControlSphere(lightControlComponent: lcc, worldAnchor: worldAnchor) else {
                    print(">>>>>> failed to create light control sphere entity when adding world anchor")
                    return
                }
                lightEntities[worldAnchor.id] = lightControlEntity
                worldAnchors[worldAnchor.id] = worldAnchor
                contentRoot.addChild(lightControlEntity)
                print("added light control entity successfully")
                
            case .updated:
                print(">>>>>> updating world anchor")
                worldAnchors[worldAnchor.id] = worldAnchor
                // This means the position of the anchor is updated so we need to update the position of the associated entity
                guard let entity = lightEntities[worldAnchor.id] else {
                    print("No existing world tracking entity found.")
                    return
                }
                
                entity.transform = Transform(matrix: worldAnchor.originFromAnchorTransform)
                
            case .removed:
                print(">>>>>> removing world anchor")
                lightEntities[worldAnchor.id]?.removeFromParent()
                lightEntities.removeValue(forKey: worldAnchor.id)
                worldAnchors.removeValue(forKey: worldAnchor.id)
                lightsInfoPersistenceManager.removeLightControlComponent(withWorldAnchorID: worldAnchor.id)
                
                // Clear current selection if it matches the removed control.
                if let selected = currentlySelectedComponent, selected.worldAnchorID == worldAnchor.id {
                    currentlySelectedComponent = nil
                    currentlySelectedType = .none
                    currentLightControlName = nil
                    selectedLightControlEntity = Entity()
                }
            }
        }
    }
    
    func removeAllWorldAnchors() async {
        for (id, _) in worldAnchors {
            do {
                try await worldTracking.removeAnchor(forID: id)
            } catch {
                print("Failed to remove world anchor id \(id).")
            }
        }
    }
    
    /// Creates a world anchor with the input transform and adds the anchor to the world tracking provider.
    func addWorldAnchor(at transform: simd_float4x4, type: LightControlType, previousLightControlComponent: LightControlComponent? = nil) async -> UUID? {
        print("Adding world anchor")
        let worldAnchor = WorldAnchor(originFromAnchorTransform: transform)
        
        var lightControlComponent = previousLightControlComponent ?? LightControlComponent()
        lightControlComponent.type = type
        lightControlComponent.worldAnchorID = worldAnchor.id
        print("saving lightControlComponent in persistence manager")
        lightsInfoPersistenceManager.addLightControlComponent(lightControlComponent)
        
        do {
            print("world tracking adding world anchor \(worldAnchor.id)")
            try await self.worldTracking.addAnchor(worldAnchor)
            return worldAnchor.id
        } catch {
            // Adding world anchors can fail, for example when you reach the limit
            // for total world anchors per app.
            print("Failed to add world anchor \(worldAnchor.id) with error: \(error).")
            return nil
        }
    }
    
    func removeWorldAnchor(id: UUID) async {
        do {
            try await self.worldTracking.removeAnchor(forID: id)
        } catch {
            print("Failed to remove world anchor \(id) with error: \(error).")
        }
    }
    
    func updateWorldAnchor(id: UUID, transform: simd_float4x4) async -> UUID? {
        
        let lcc = lightsInfoPersistenceManager.lightControlComponents.first { lightControlComponent in
            lightControlComponent.worldAnchorID == id
        }
        guard let lcc else {
            return nil
        }
        
        let type = lcc.type
        lightsInfoPersistenceManager.removeLightControlComponent(withWorldAnchorID: lcc.worldAnchorID)
        // check for robustness, this might be introducing bugs
        
        await removeWorldAnchor(id: id)
        do {
            try await Task.sleep(for: .milliseconds(1000))
        } catch {
            print(error.localizedDescription)
        }
        
        return await addWorldAnchor(at: transform, type: type, previousLightControlComponent: lcc)
    }
    
    func getCurrentDeviceTransform() -> Transform? {
        // Query the device anchor at the current time.
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return nil }
        
        // Find the transform of the device.
        let deviceTransform = Transform(matrix: deviceAnchor.originFromAnchorTransform)
        return deviceTransform
    }
    
    func addLightControl() {
        print("Adding light control")
        Task {
            guard let deviceTransform = getCurrentDeviceTransform() else {
                print("failed to get device transform")
                return
            }
            let forward = normalize(-deviceTransform.matrix.columns.2.xyz)
            let currentPosition = deviceTransform.translation
            let targetPosition = currentPosition + forward * 0.5
            
            var transformMatrix = matrix_identity_float4x4
            transformMatrix.columns.3 = SIMD4<Float>(targetPosition.x, targetPosition.y, targetPosition.z, 1)
            
            _ = await addWorldAnchor(at: transformMatrix, type: .light)
        }
    }
    
    func addGroupControl() {
        Task {
            guard let deviceTransform = getCurrentDeviceTransform() else { return }
            let forward = normalize(-deviceTransform.matrix.columns.2.xyz)
            let currentPosition = deviceTransform.translation
            let targetPosition = currentPosition + forward * 0.5
            
            var transformMatrix = matrix_identity_float4x4
            transformMatrix.columns.3 = SIMD4<Float>(targetPosition.x, targetPosition.y, targetPosition.z, 1)
            _ = await addWorldAnchor(at: transformMatrix, type: .group)
        }
    }
    
    // MARK: - Removing light / group controls
    
    /// Removes a light or group control given its world‑anchor identifier.
    /// This deletes the associated RealityKit entity, removes the ARKit world anchor,
    /// and clears the persisted `LightControlComponent`.
    func removeLightOrGroupControl(worldAnchorID id: UUID) {
        // Remove the ARKit world anchor asynchronously.
        Task {
            await removeWorldAnchor(id: id)
        }
    }
    
    /// Convenience helper that removes whichever control is currently selected (if any).
    func removeSelectedLightOrGroupControl() {
        guard let selected = currentlySelectedComponent else { return }
        removeLightOrGroupControl(worldAnchorID: selected.worldAnchorID)
    }
    
    func createLightControlSphere(lightControlComponent: LightControlComponent, worldAnchor: WorldAnchor) async -> Entity? {
        let sphereMesh = MeshResource.generateSphere(radius: 0.1)
        let sphereMaterial = SimpleMaterial(color: lightControlComponent.type == .light ? .red : .green, roughness: 0, isMetallic: false)
        
        let sphere = ModelEntity(mesh: sphereMesh, materials: [sphereMaterial])
        
        // Enables gestures on the preview sphere.
        // Looking at the preview and using a pinch gesture causes a world anchored sphere to appear.
        sphere.generateCollisionShapes(recursive: false, static: true)
        // Ensures the preview only accepts indirect input (for tap gestures).
        sphere.components.set(InputTargetComponent(allowedInputTypes: [.indirect]))
        
        sphere.components.set(CollisionComponent(shapes:[.generateSphere(radius: 0.15)]))
        
        sphere.components.set(OpacityComponent(opacity: isEditingLightSetup ? 0.5 : 0.05)) // if the opacity component goes to zero, the the tap gesture doesn't work
        
        sphere.transform = Transform(matrix: worldAnchor.originFromAnchorTransform)
        
        sphere.components.set(lightControlComponent)
        
        return sphere
    }
    
    func toggleVisibilityOfLightEntities() {
        for entity in lightEntities.values {
            
            guard var opacityComponent = entity.components[OpacityComponent.self] else { continue }
            if isEditingLightSetup {
                opacityComponent.opacity = 0.5
            } else {
                opacityComponent.opacity = 0.1
            }
            entity.components.set(opacityComponent)
            
        }
    }
    
    
    func onLightEditingToggleChanged() {
        toggleVisibilityOfLightEntities()
        // only update anchors when dragging.
        
        // the code below updates the world anchors for all entities when the toggle for editing is turned off.
//        if !isEditingLightSetup {
//            for entity in lightEntities.values {
//                if let lcc = entity.components[LightControlComponent.self] {
//                    Task {
//                        await updateWorldAnchor(id: lcc.worldAnchorID, transform: entity.transformMatrix(relativeTo: nil))
//                    }
//                }
//            }
//        }
    }
}
