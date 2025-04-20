//
//  HueBridgeMDNS.swift
//  Philips Hue Control
//
//  Created by Sarang Borude on 3/16/25.
//
//This class handles discovering of the IP Address of your local Hue Bridge using mDNS

import Foundation
import Network

@Observable
class HueLocalDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var discoveredServices: [NetService] = []
    var hueBridgeIP: String?
    private override init() {
        super.init()
        browser.delegate = self
        startDiscovery()
    }
    
    public static let shared = HueLocalDiscovery()
    
    func startDiscovery() {
        browser.searchForServices(ofType: "_hue._tcp.", inDomain: "")
    }
    
    // MARK: - NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        discoveredServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let hostName = sender.hostName, let addresses = sender.addresses {
            addresses.forEach { address in
                let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(hostName), port: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(sender.port)))
                print("Resolved service at \(endpoint)")
                
                if let ipString = ipAddressString(from: address) {
                    print("Resolved Hue Bridge IP: \(ipString)")
                    // At this point, you have the raw IP address (e.g. 192.168.x.x)
                    // You can store or use this IP address here.
                    hueBridgeIP = ipString
                }
                
            }
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Failed resolving service: \(errorDict)")
    }
    
    /// Parses a sockaddr Data into a string IP address (IPv4 or IPv6).
    private func ipAddressString(from addressData: Data) -> String? {
        return addressData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> String? in
            guard let addrPtr = pointer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else {
                return nil
            }
            
            let family = sa_family_t(addrPtr.pointee.sa_family)
            
            if family == sa_family_t(AF_INET) {
                // IPv4
                var addr = pointer.bindMemory(to: sockaddr_in.self).baseAddress!.pointee
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let conversion = inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                if conversion != nil {
                    return String(cString: buffer)
                }
                
            } else if family == sa_family_t(AF_INET6) {
                return nil // we don't need ipv6 right now
                // IPv6 (less common for Hue, but possible in future)
                var addr = pointer.bindMemory(to: sockaddr_in6.self).baseAddress!.pointee
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                let conversion = inet_ntop(AF_INET6, &addr.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
                if conversion != nil {
                    return String(cString: buffer)
                }
            }
            
            return nil
        }
    }
}

