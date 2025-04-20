//
//  HueBridgeUserManager.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/16/25.
//
import Foundation
import Security
import UIKit

/// Simple error cases for Hue Bridge interactions
enum HueBridgeError: Error, Equatable {
    case invalidURL
    case noDataReceived
    case invalidResponse
    case linkNotPressed  // Hue error 101
    case unknown(String)
}

/// A manager that can register a user on a Hue Bridge and store the resulting username in the Keychain.
@Observable
class HueBridgeUserManager {
    
    // MARK: - Properties
    
    private let deviceName = UIDevice.current.name
    private let keychainUsernameKey = "HueBridgeUsername"  // Key used to store/retrieve in Keychain
    
    /// Optional in-memory cache of the username to avoid repeated Keychain lookups.
    private var cachedUsername: String?
    
    public var isUsernameDiscovered = false
    
    private init() {
        isUsernameDiscovered = username != nil
    }
    
    public static let shared: HueBridgeUserManager = .init()
    
    // MARK: - Public Methods
    
    /// Public read-only property so other classes can quickly access the username.
    /// It returns the cached value if available, otherwise tries to load from Keychain.
    public var username: String? {
        if let cachedUsername = cachedUsername {
            isUsernameDiscovered = true
            return cachedUsername
        } else {
            let storedUsername = retrieveUsernameFromKeychain()
            if let storedUsername = storedUsername {
                // Store in cache for future calls
                isUsernameDiscovered = true
                cachedUsername = storedUsername
            }
            return storedUsername
        }
    }
    
    public func waitUntilUsernameDiscovered() async {
        
        let pollInterval: UInt64 = 1_000_000_000 // 1 seconds
        
        while !isUsernameDiscovered {
            print("Waiting for user name to be discovered...")
            try? await Task.sleep(nanoseconds: pollInterval)
        }
        print("User name discovered")
    }
    
    /// Ensures we have an authorized username. If none is found in the Keychain,
    /// attempts registration. If link button not pressed, prompts user to do so,
    /// then tries again.
    ///
    func ensureAuthorized(completion: @escaping (Result<String, Error>) -> Void) {
        // 1. Check if we already have a stored username (already authorized).
        print("Ensuring user name is authorized...")
        if let existingUsername = retrieveUsernameFromKeychain() {
            completion(.success(existingUsername))
            isUsernameDiscovered = true
            return
        }
        
        // 2. No username stored. We need to register with the Hue Bridge.
        registerUser { [weak self] result in
            switch result {
            case .success(let newUsername):
                // Store in Keychain and return
                self?.storeUsernameInKeychain(newUsername)
                completion(.success(newUsername))
                self?.isUsernameDiscovered = true
                
            case .failure(let error):
                self?.isUsernameDiscovered = false
                // 3. If link button is not pressed, prompt user to press it and retry
                if let hueError = error as? HueBridgeError, hueError == .linkNotPressed {
                    // Prompt user to press link button (e.g., show an alert).
                    // Once the user confirms they have pressed it, we try again:
                    self?.registerUser { secondAttemptResult in
                        switch secondAttemptResult {
                        case .success(let finalUsername):
                            self?.storeUsernameInKeychain(finalUsername)
                            completion(.success(finalUsername))
                            
                        case .failure(let finalError):
                            completion(.failure(finalError))
                        }
                    }
                } else {
                    // Some other error
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Registers a new user on the Hue Bridge by performing a `POST` to `<bridge_ip>/api`.
    /// On success, returns the `username` in the completion. Otherwise, returns an error.
    private func registerUser(completion: @escaping (Result<String, Error>) -> Void) {
        
        guard
            let bridgeIp = HueBridgeDiscoverer.shared.bridgeIPAddress,
            let url = URL(string: "http://\(bridgeIp)/api") else {
            completion(.failure(HueBridgeError.invalidURL))
            return
        }
        
        // 1. Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 2. Set up the body, e.g. {"devicetype":"my_hue_app#deviceName"}
        let requestBody = ["devicetype": "my_hue_app#\(deviceName)"]
        do {
            let data = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = data
        } catch {
            completion(.failure(error))
            return
        }
        print("Trying to get username")
        // 3. Execute the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            print("Got response")
            // Basic network error check
            if let error = error {
                completion(.failure(error))
                if let httpResponse = response as? HTTPURLResponse {
                    print("Status code: \(httpResponse.statusCode)")
                    print("Headers: \(httpResponse.allHeaderFields)")
                }
                return
            }
            
            // Ensure data exists
            guard let data = data else {
                completion(.failure(HueBridgeError.noDataReceived))
                return
            }
            
            // 4. Parse the response
            do {
                // Hue's response is typically an array of objects.
                // e.g.: [{"success":{"username":"some-username"}}]
                //       [{"error":{"type":101,"address":"","description":"link button not pressed"}}]
                if let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]],
                   let firstItem = jsonArray.first {
                    
                    if let successDict = firstItem["success"] as? [String: Any],
                       let username = successDict["username"] as? String {
                        // Registration success, returned a username
                        completion(.success(username))
                        
                    } else if let errorDict = firstItem["error"] as? [String: Any],
                              let errorType = errorDict["type"] as? Int {
                        // Check for link-not-pressed (error 101)
                        if errorType == 101 {
                            completion(.failure(HueBridgeError.linkNotPressed))
                        } else {
                            let description = errorDict["description"] as? String ?? "Unknown error"
                            completion(.failure(HueBridgeError.unknown(description)))
                        }
                    } else {
                        // Invalid or unexpected structure
                        completion(.failure(HueBridgeError.invalidResponse))
                    }
                } else {
                    completion(.failure(HueBridgeError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Keychain Management
    
    /// Stores the given username in the Keychain.
    private func storeUsernameInKeychain(_ username: String) {
        guard let usernameData = username.data(using: .utf8) else { return }
        
        // Define a query to delete any existing item under this account key (clean slate).
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : keychainUsernameKey
        ]
        SecItemDelete(query as CFDictionary)  // Ignore status; it's OK if nothing is found
        
        // Define attributes for the new item
        let attributes: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : keychainUsernameKey,
            kSecValueData as String   : usernameData
        ]
        
        // Attempt to add to Keychain
        SecItemAdd(attributes as CFDictionary, nil)
    }
    
    /// Retrieves the stored Hue username from the Keychain. Returns `nil` if not found.
    private func retrieveUsernameFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : keychainUsernameKey,
            kSecReturnData as String  : kCFBooleanTrue as Any,
            kSecMatchLimit as String  : kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let username = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        
        return username
    }
    
    func removeKeychainValue(forAccount account: String) -> Bool {
        // Define a query that matches the keychain item you want to remove.
        let query: [String: Any] = [
            kSecClass as String       : kSecClassGenericPassword,
            kSecAttrAccount as String : account
        ]
        
        // Delete the item from the Keychain
        let status = SecItemDelete(query as CFDictionary)
        
        // `errSecSuccess` indicates successful deletion
        return status == errSecSuccess
    }
    
    public func clearKeychain() {
        let success = removeKeychainValue(forAccount: keychainUsernameKey)
        if success {
            print("Keychain value removed successfully.")
        } else {
            print("Failed to remove value from Keychain.")
        }
    }
}
