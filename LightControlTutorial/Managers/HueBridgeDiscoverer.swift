import SwiftUI

struct HueBridge: Codable {
    let id: String
    let internalipaddress: String
    let port: Int
}

@Observable
class HueBridgeDiscoverer {
    var bridges: [HueBridge] = []
    var firstBridge: HueBridge?
    
    private let discoveryURL = "http://discovery.meethue.com/"
    
    public var bridgeIPAddress: String? {
        return firstBridge?.internalipaddress
    }
    
    private init() {
        discoverBridges()
    }
    
    public static let shared = HueBridgeDiscoverer()
    
    func discoverBridges() {
        
        guard let url = URL(string: discoveryURL) else {
            print("Invalid discovery URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Discovery failed: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data returned from discovery API")
                return
            }
            
            do {
                let discoveredBridges = try JSONDecoder().decode([HueBridge].self, from: data)
                DispatchQueue.main.async {
                    self.bridges = discoveredBridges
                    print("Discovered bridges:", self.bridges)
                    if let firstBridge = discoveredBridges.first {
                        self.firstBridge = firstBridge
                    }
                }
            } catch {
                print("Failed decoding discovery response:", error)
            }
        }.resume()
    }
}
