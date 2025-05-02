//
//  ProjectileCollisionSystem.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/23/25.
//

import RealityKit
import RealityKitContent
import Combine
import UIKit
import SwiftUI

class ProjectileCollisionSystem: System {
        
    let projectileQuery = EntityQuery(where: .has(ProjectileComponent.self))
  
    var projectileEntity = Entity()

    var cancellable: Cancellable
  
    static var HasFoundProjectile = false
    
    public static var onCollision : (() -> Void)?
    
    var hueControlManager = HueControlManager.shared

    required init(scene: RealityKit.Scene) {
        cancellable = scene.subscribe(to: CollisionEvents.Began.self,on: projectileEntity) { event in
            print("Collision happened between \(event.entityA.name) and \(event.entityB.name)")
            
            event.entityB.removeFromParent()
        }
    }
    
    func update(context: SceneUpdateContext) {
        
        // check for collision, if collision happens do something.
        
        if(!Self.HasFoundProjectile) {
            context.scene.performQuery(projectileQuery).forEach { projectile in
                projectileEntity = projectile
                Self.HasFoundProjectile = true

                cancellable = context.scene.subscribe(to: CollisionEvents.Began.self, on: projectileEntity) { event in
                    print("Collision happened between \(event.entityA.name) and \(event.entityB.name)")
                    
                    guard let lcc = event.entityB.components[LightControlComponent.self] else { return }
                    guard let pc = event.entityA.components[ProjectileComponent.self] else { return }
                    
                    // Send the control command based on component type
                    if lcc.type == .light {
                        self.hueControlManager.controlLight(lightName: lcc.name, state: ["on": true, "hue": pc.hue, "sat": pc.saturation, "bri": pc.brightness]) { result in
                            switch result {
                            case .success:
                                break
                            case .failure(let error):
                                print("Error: \(error)")
                            }
                        }
                    } else if lcc.type == .group {
                            self.hueControlManager.controlGroup(groupName: lcc.name, action: ["on": true, "hue": pc.hue, "sat": pc.saturation, "bri": pc.brightness]) { result in
                            switch result {
                            case .success:
                                break
                            case .failure(let error):
                                print("Error: \(error)")
                            }
                        }
                    }
                   
                    Self.onCollision?() // call the callback so that other classes can take the action to reset when collision happens.
                    
                    Self.HasFoundProjectile = false
                }
            }
        }
    }
}

