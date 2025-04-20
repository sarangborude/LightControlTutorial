//
//  LightsInfoPersistenceManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/21/25.
//
import ARKit
import SwiftUI
import Foundation

@Observable
class LightsInfoPersistenceManager {
    
    private let fileName = "lightControls.json"
    public private(set) var lightControlComponents: [LightControlComponent] = []
    
    public static let shared = LightsInfoPersistenceManager()
    
    private init() {
    
    }


    // MARK: Methods to persist light information across launches
    
    // MARK: - Add a New Light Control Component
    func addLightControlComponent(_ component: LightControlComponent) {
        lightControlComponents.append(component)
        saveLightControlComponentsToDisk()
    }
    
    // MARK: - Remove a Component by ID
    func removeLightControlComponent(withWorldAnchorID worldAnchorID: UUID) {
        lightControlComponents.removeAll { $0.worldAnchorID == worldAnchorID }
        saveLightControlComponentsToDisk()
    }
    
    // MARK: - Update an Existing Component
    func updateLightControlComponent(_ updatedComponent: LightControlComponent) {
        if let index = lightControlComponents.firstIndex(where: { $0.worldAnchorID == updatedComponent.worldAnchorID }) {
            lightControlComponents[index] = updatedComponent
            saveLightControlComponentsToDisk()
        }
    }
    
    // MARK: - Get All lightControlComponents
    func getlightControlComponents() -> [LightControlComponent] {
        return lightControlComponents
    }
    
    // MARK: - Save to Disk
    func saveLightControlComponentsToDisk() {
        let url = getFileURL()
        do {
            let data = try JSONEncoder().encode(lightControlComponents)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save LightControlComponents: \(error)")
        }
    }
    
    // MARK: - Load from Disk
    func loadLightControlComponentsFromDisk() {
        let url = getFileURL()
        do {
            let data = try Data(contentsOf: url)
            lightControlComponents = try JSONDecoder().decode([LightControlComponent].self, from: data)
        } catch {
            print("Failed to load LightControlComponents: \(error)")
        }
    }
    
    // MARK: - File URL
    private func getFileURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent(fileName)
    }
}
