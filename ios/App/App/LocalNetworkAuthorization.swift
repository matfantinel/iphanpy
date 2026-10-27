import Foundation
import Network

@objc(LocalNetworkAuthorization)
public class LocalNetworkAuthorization: NSObject {
    
    @objc public static func trigger() {
        // This triggers the Local Network permission dialog
        let connection = NWConnection(host: "224.0.0.251", port: 5353, using: .udp)
        connection.start(queue: .global())
        
        // Cancel after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            connection.cancel()
        }
    }
}
