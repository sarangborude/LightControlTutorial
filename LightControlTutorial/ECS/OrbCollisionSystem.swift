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

class OrbCollisionSystem: System {
    
    static var appModel: AppModel!
    let OrbQuery = EntityQuery(where: .has(OrbComponent.self))
    
    var cancellables: [Cancellable] = []
    let orbEntity = Entity()
    
    public static var onCollision : (() -> Void)?
    
    var hueControlManager = HueControlManager.shared
    
    required init(scene: RealityKit.Scene) { }
    
    func update(context: SceneUpdateContext) {
        guard Self.appModel.lightControlMode == .orbsOnHand else { return }
        // check for collision, if collision happens do something.
        
        //print("Discovering orbs")
        let orbs = context.entities(matching: OrbQuery, updatingSystemWhen: .rendering)
        //print("finished discovering orbs, count: \(orbs)")
        cancellables.removeAll()
        
        for orb in orbs {
            //print("adding cancellable for orb")
            let cancellable = context.scene.subscribe(to: CollisionEvents.Began.self, on: orb) { event in
                print("Collision happened between \(event.entityA.name) and \(event.entityB.name)")
                
                guard let lcc = event.entityB.components[LightControlComponent.self] else {
                    print ("Collision: LightControlComponent not found")
                    return }
                guard let oc = event.entityA.components[OrbComponent.self] else {
                    print ("Collision: OrbComponent not found")
                    return }
                
                // Send the control command based on component type
                if lcc.type == .light {
                    self.hueControlManager.controlLight(lightName: lcc.name, state: ["on": true, "hue": oc.hue, "sat": oc.saturation, "bri": oc.brightness]) { result in
                        switch result {
                        case .success:
                            break
                        case .failure(let error):
                            print("Error: \(error)")
                        }
                    }
                } else if lcc.type == .group {
                    self.hueControlManager.controlGroup(groupName: lcc.name, action: ["on": true, "hue": oc.hue, "sat":oc.saturation, "bri": oc.brightness]) { result in
                        switch result {
                        case .success:
                            break
                        case .failure(let error):
                            print("Error: \(error)")
                        }
                    }
                }
                
                Self.onCollision?() // call the callback so that other classes can take the action to reset when collision happens. Not used in this prototype
                
                event.entityA.removeFromParent()
            }
            cancellables.append(cancellable)
            
        }
    }
    //}
}

