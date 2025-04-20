//
//  HueControlManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/16/25.
//

import Foundation

/// Simple class for interacting with a Hue Bridge
@Observable
class HueControlManager {
    
    // MARK: - Properties
    let hueBridgeDiscoverer = HueBridgeDiscoverer.shared
    let hueBridgeUserManager = HueBridgeUserManager.shared
    let hueLocalDiscovery = HueLocalDiscovery.shared
    
    /// Public dictionaries you can read from your UI:
    var lights: [String: LightInfo] = [:]
    var groups: [String: GroupInfo] = [:]
    
    var lightNames: [String: String] = [:] // e.g. ["1": "Living Room Lamp", "2": "Kitchen Bulb"]
    var groupNames: [String: String] = [:] // e.g. ["1": "Living Room", "2": "Kitchen"]
    
    // MARK: - Initialization
    
    private init() {}
    public static let shared = HueControlManager()
    
    // MARK: - Public Methods
    
    /// GET *everything* in one shot (`/api/<username>`) and extract lights & groups.
    /// - Caches both dictionaries and returns them via the completion handler.
    func findLightsAndGroups(
        completion: @escaping (Result<(lights: [String: LightInfo],
                                       groups: [String: GroupInfo]), Error>) -> Void)
    {
        guard let bridgeIp = hueLocalDiscovery.hueBridgeIP else {
            fatalError("Bridge IP doesn't exist")
        }
        guard let username = hueBridgeUserManager.username else {
            fatalError("Username doesn't exist")
        }
        
        // Request the root JSON which contains "lights", "groups", "config", etc.
        guard let url = URL(string: "http://\(bridgeIp)/api/\(username)") else {
            completion(.failure(HueError.invalidURL))
            return
        }
        
        print("Attempting to GET /api/\(username)") // remove this
        
//        var config = URLSessionConfiguration.default
//        config.timeoutIntervalForRequest = 5
//        let session = URLSession(configuration: config)
//        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(HueError.noData))
                return
            }
            
            do {
                // Parse the root JSON object
                if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    // ---- Lights ----
                    var parsedLights: [String: LightInfo] = [:]
                    if let lightsDict = root["lights"] as? [String: Any] {
                        for (lightId, lightObj) in lightsDict {
                            if let lightInfoDict = lightObj as? [String: Any],
                               let name = lightInfoDict["name"] as? String {
                                parsedLights[lightId] = LightInfo(name: name)
                            }
                        }
                    }
                    
                    // ---- Groups ----
                    var parsedGroups: [String: GroupInfo] = [:]
                    if let groupsDict = root["groups"] as? [String: Any] {
                        for (groupId, groupObj) in groupsDict {
                            if let groupInfoDict = groupObj as? [String: Any],
                               let name  = groupInfoDict["name"]  as? String,
                               let type  = groupInfoDict["type"]  as? String,
                               let lights = groupInfoDict["lights"] as? [String] {
                                parsedGroups[groupId] = GroupInfo(name: name,
                                                                  type: type,
                                                                  lights: lights)
                            }
                        }
                    }
                    
                    // Update caches
                    self.lights      = parsedLights
                    self.lightNames  = parsedLights.mapValues { $0.name }
                    self.groups      = parsedGroups
                    self.groupNames  = parsedGroups.mapValues { $0.name }
                    
                    print(self.lightNames)
                    print(self.groupNames)
                    
                    completion(.success((lights: parsedLights, groups: parsedGroups)))
                } else {
                    completion(.failure(HueError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    /// GET all lights: https://<bridge_ip>/api/<username>/lights
    /// - Fills `lights` and `lightNames` dictionaries for easy reference.
    func findLights(completion: @escaping (Result<[String: LightInfo], Error>) -> Void) {
        print("Starting to find lights")
        guard let bridgeIp = hueLocalDiscovery.hueBridgeIP else {
            fatalError("Bridge IP doesn't exist")
        }
        guard let username = hueBridgeUserManager.username else {
            fatalError("Username doesn't exist")
        }
        guard let url = URL(string: "http://\(bridgeIp)/api/\(username)/lights") else {
            completion(.failure(HueError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                print("Got error response")
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                
                return
            }
            guard let data = data else {
                completion(.failure(HueError.noData))
                return
            }
            
            do {
                // Hue returns a dictionary keyed by light ID: "1", "2", ...
                // Each value is a dictionary with "state", "name", etc.
                if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    
                    var results: [String: LightInfo] = [:]
                    
                    for (lightId, lightObject) in dict {
                        if let lightDict = lightObject as? [String: Any],
                           let name = lightDict["name"] as? String {
                            let info = LightInfo(name: name)
                            results[lightId] = info
                        }
                    }
                    
                    // Cache the results in memory
                    self.lights = results
                    // Also create a simple dictionary of [lightId: lightName]
                    self.lightNames = results.mapValues { $0.name }
                    
                    completion(.success(results))
                } else {
                    completion(.failure(HueError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    /// GET all groups: https://<bridge_ip>/api/<username>/groups
    /// - Fills `groups` and `groupNames` dictionaries for easy reference.
    func findGroups(completion: @escaping (Result<[String: GroupInfo], Error>) -> Void) {
        print("Starting to find groups...")
        guard let bridgeIp = hueLocalDiscovery.hueBridgeIP else {
            fatalError("Bridge IP doesn't exist")
        }
        guard let username = hueBridgeUserManager.username else {
            fatalError("Username doesn't exist")
        }
        guard let url = URL(string: "http://\(bridgeIp)/api/\(username)/groups") else {
            completion(.failure(HueError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print(error.localizedDescription)
                completion(.failure(error))
                print("Got error response")
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                return
            }
            guard let data = data else {
                print(HueError.noData.localizedDescription)
                completion(.failure(HueError.noData))
                return
            }
            
            do {
                // Hue returns a dictionary keyed by group ID: "1", "2", ...
                // Each value is a dictionary with "name", "type", "lights":[], etc.
                if let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    
                    var results: [String: GroupInfo] = [:]
                    
                    for (groupId, groupObject) in dict {
                        if let groupDict = groupObject as? [String: Any],
                           let name = groupDict["name"] as? String,
                           let type = groupDict["type"] as? String,
                           let lights = groupDict["lights"] as? [String] {
                            
                            let info = GroupInfo(name: name, type: type, lights: lights)
                            results[groupId] = info
                        }
                    }
                    
                    // Cache the results
                    self.groups = results
                    self.groupNames = results.mapValues { $0.name }
                   
                    completion(.success(results))
                } else {
                    completion(.failure(HueError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Controlling Lights (by ID and by Name)
    
    /// Control an individual light by ID:
    /// PUT https://<bridge_ip>/api/<username>/lights/<light_id>/state
    func controlLight(lightId: String, state: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let bridgeIp = hueLocalDiscovery.hueBridgeIP else {
            fatalError("Bridge IP doesn't exist")
        }
        guard let username = hueBridgeUserManager.username else {
            fatalError("Username doesn't exist")
        }
        guard let url = URL(string: "http://\(bridgeIp)/api/\(username)/lights/\(lightId)/state") else {
            completion(.failure(HueError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: state, options: [])
            request.httpBody = bodyData
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }.resume()
    }
    
    /// Control an individual light by *Name*.
    /// Finds the matching lightId from `lightNames` and calls the ID-based version.
    func controlLight(lightName: String, state: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        // Find the lightId whose name matches `lightName`.
        // Note: if multiple lights share the same name, this picks the first match.
        guard let (lightId, _) = lightNames.first(where: { $0.value == lightName }) else {
            completion(.failure(HueError.notFound("No light found with name: \(lightName)")))
            return
        }
        
        controlLight(lightId: lightId, state: state, completion: completion)
    }
    
    // MARK: - Controlling Groups (by ID and by Name)
    
    /// Control an entire group by ID:
    /// PUT https://<bridge_ip>/api/<username>/groups/<group_id>/action
    func controlGroup(groupId: String, action: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let bridgeIp = hueLocalDiscovery.hueBridgeIP else {
            fatalError("Bridge IP doesn't exist")
        }
        guard let username = hueBridgeUserManager.username else {
            fatalError("Username doesn't exist")
        }
        
        guard let url = URL(string: "http://\(bridgeIp)/api/\(username)/groups/\(groupId)/action") else {
            completion(.failure(HueError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let bodyData = try JSONSerialization.data(withJSONObject: action, options: [])
            request.httpBody = bodyData
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }.resume()
    }
    
    /// Control a group by *Name*.
    /// Finds the matching groupId from `groupNames` and calls the ID-based version.
    func controlGroup(groupName: String, action: [String: Any], completion: @escaping (Result<Void, Error>) -> Void) {
        guard let (groupId, _) = groupNames.first(where: { $0.value == groupName }) else {
            completion(.failure(HueError.notFound("No group found with name: \(groupName)")))
            return
        }
        
        controlGroup(groupId: groupId, action: action, completion: completion)
    }
    
    // MARK: - Getting Status
    
    /// GET the status of an individual light: https://<bridge_ip>/api/<username>/lights/<light_id>
    func getLightStatus(lightId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let bridgeIp = hueLocalDiscovery.hueBridgeIP else {
            fatalError("Bridge IP doesn't exist")
        }
        guard let username = hueBridgeUserManager.username else {
            fatalError("Username doesn't exist")
        }
        guard let url = URL(string: "http://\(bridgeIp)/api/\(username)/lights/\(lightId)") else {
            completion(.failure(HueError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(HueError.noData))
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(HueError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    /// GET the status of an entire group: https://<bridge_ip>/api/<username>/groups/<group_id>
    func getGroupStatus(groupId: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let bridgeIp = hueLocalDiscovery.hueBridgeIP else {
            fatalError("Bridge IP doesn't exist")
        }
        guard let username = hueBridgeUserManager.username else {
            fatalError("Username doesn't exist")
        }
        guard let url = URL(string: "http://\(bridgeIp)/api/\(username)/groups/\(groupId)") else {
            completion(.failure(HueError.invalidURL))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(HueError.noData))
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    completion(.success(json))
                } else {
                    completion(.failure(HueError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    /// GET the status of an individual light by name.
    func getLightStatus(lightName: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let (lightId, _) = lightNames.first(where: { $0.value == lightName }) else {
            completion(.failure(HueError.notFound("No light found with name: \(lightName)")))
            return
        }
        getLightStatus(lightId: lightId, completion: completion)
    }

    /// GET the status of a group by name.
    func getGroupStatus(groupName: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        guard let (groupId, _) = groupNames.first(where: { $0.value == groupName }) else {
            completion(.failure(HueError.notFound("No group found with name: \(groupName)")))
            return
        }
        getGroupStatus(groupId: groupId, completion: completion)
    }
    
    // MARK: - Helper Types & Errors
    
    struct LightInfo {
        let name: String
        // Optionally, add more fields (type, modelid, etc.)
    }
    
    struct GroupInfo {
        let name: String
        let type: String   // "Room", "Zone", etc.
        let lights: [String]
    }
    
    enum HueError: Error {
        case invalidURL
        case noData
        case invalidResponse
        case notFound(String)
    }
}

enum LightControlType: Codable {
    case light
    case group
    case none
}
