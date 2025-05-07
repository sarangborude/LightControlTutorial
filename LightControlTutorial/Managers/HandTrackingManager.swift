//
//  HandTrackingManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/23/25.
//

import RealityKit
import ARKit
import UIKit

@MainActor
@Observable
class HandTrackingManager {
    
    let handTracking = HandTrackingProvider()
    
    // Separate handlers for different gestures for different operating modes
    var slingShotGestureManager: SlingShotGestureManager?
    var orbsOnHandGestureManager: OrbsOnHandGestureManager?
    
    var appModel: AppModel
    
    var gestureMonitoringTask: Task<Void, Never>? = nil
    
    init(appModel: AppModel) {
        self.appModel = appModel
        
        // Listen for mode changes. // leave this for part 4
           appModel.onLightControlModeChanged = {
               print("Light Control Mode Changed to \(appModel.lightControlMode)")
               
               self.slingShotGestureManager?.removeEntitiesForFingersAndProjectile()
               self.orbsOnHandGestureManager?.removeOrbRing()
               
               switch appModel.lightControlMode {
               case .lookAndPinch:
                   self.slingShotGestureManager = nil
                   self.orbsOnHandGestureManager = nil
               case .slingShot:
                   // Initialize the SlingShotManager and clean up orb-related entities.
                   self.slingShotGestureManager = SlingShotGestureManager(appModel: appModel, handTracking: self.handTracking)
                   self.orbsOnHandGestureManager = nil
               case .orbsOnHand:
                   // Initialize the OrbsOnHandGestureManager and clean up slingshot entities
                   self.slingShotGestureManager = nil
                   self.orbsOnHandGestureManager = OrbsOnHandGestureManager(appModel: appModel, handTracking: self.handTracking)
               }
               
               // cancel existing tracking task
               self.gestureMonitoringTask?.cancel()
               
               self.gestureMonitoringTask =  Task {
                   await self.monitorGestures()
               }
           }
    }

   func monitorGestures() async {
       
       await slingShotGestureManager?.monitorPeaceGesture()
       
       await orbsOnHandGestureManager?.monitorPalmUpGesture()
    }
}
