//
//  SlingshotManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/23/25.
//

import simd
import RealityKit

struct SlingShotMechanismManager {
    // Maximum allowed pull distance (in your scene's units)
    let maxPullDistance: Float = 0.5
    // Multiplier to scale the impulse force applied to the projectile
    let forceMultiplier: Float = -30.0

    // Store the starting drag position for the slingshot pull
    var initialDragPosition: SIMD3<Float>?
    // Current offset from the initial drag point (after clamping)
    var currentDragOffset: SIMD3<Float> = .zero

    mutating func beginDrag(at position: SIMD3<Float>) {
        initialDragPosition = position
        currentDragOffset = .zero
    }

    mutating func updateDrag(to newPosition: SIMD3<Float>, newInitialPosition: SIMD3<Float>?) {
        initialDragPosition = newInitialPosition
        guard let start = initialDragPosition else { return }
        var offset = newPosition - start
        let dragDistance = length(offset)
        // Clamp the drag offset if it exceeds the maximum
        if dragDistance > maxPullDistance {
            offset = (offset / dragDistance) * maxPullDistance
        }
        currentDragOffset = offset
    }

    // Calculate the impulse force to apply to the projectile based on the current drag offset
    func computedImpulse() -> SIMD3<Float> {
        let pullStrength = length(currentDragOffset)
        guard pullStrength > 0 else { return .zero }
        let direction = normalize(currentDragOffset)
        return direction * pullStrength * forceMultiplier
    }
}
