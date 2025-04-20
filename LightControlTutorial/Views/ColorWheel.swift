//
//  ColorWheel.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/22/25.
//

import SwiftUI

struct ColorWheel: View {
    // A binding so that parent views can observe and modify the selected color
    @Binding var color: Color
    
    // Internally track hue and saturation so we can place the handle correctly
    @State private var currentHue: CGFloat = 0.0
    @State private var currentSaturation: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            // Make the view square and use the smaller of width/height as the wheel size
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            
            ZStack {
                // 1) Angular gradient for hue
                //    We'll map hue from 0 -> 1 (which is 0 -> 360 degrees)
                AngularGradient(gradient: Gradient(colors:
                    stride(from: 0.0, through: 1.0, by: 0.1).map {
                        Color(hue: $0, saturation: 1.0, brightness: 1.0)
                    }
                ), center: .center)
                
                // 2) Radial gradient to fade to white in the center (reducing saturation)
                RadialGradient(gradient: Gradient(colors: [
                    Color.white,
                    Color.white.opacity(0.0)
                ]), center: .center, startRadius: 0, endRadius: radius)
                
                // Mask with a circle so it’s a perfect wheel
                .mask(Circle())
                
                // 3) Draggable handle to show current color selection
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    // Position the handle based on hue/sat
                    .position(x: radius + radius * currentSaturation * cos(currentHue * 2 * .pi),
                              y: radius + radius * currentSaturation * sin(currentHue * 2 * .pi))
            }
            .frame(width: size, height: size)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Convert the drag location into (hue, saturation)
                        let dx = value.location.x - radius
                        let dy = value.location.y - radius
                        
                        // Angle in radians (0 to 2π)
                        var angle = atan2(dy, dx)
                        if angle < 0 { angle += 2 * .pi }
                        
                        // Convert angle to hue [0, 1]
                        let newHue = angle / (2 * .pi)
                        
                        // Distance from center, used for saturation [0, 1]
                        let dist = sqrt(dx*dx + dy*dy)
                        let newSaturation = min(dist / radius, 1.0)
                        
                        currentHue = newHue
                        currentSaturation = newSaturation
                        
                        // Update the bound color (fix brightness to 1.0 here)
                        color = Color(hue: Double(currentHue),
                                      saturation: Double(currentSaturation),
                                      brightness: 1.0)
                    }
            )
            // Keep our aspect ratio square
            .onAppear {
                // Initialize handle position if `color` was already set
                var h: CGFloat = 0
                var s: CGFloat = 0
                var b: CGFloat = 0
                var a: CGFloat = 0
                UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                currentHue = h
                currentSaturation = s
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
