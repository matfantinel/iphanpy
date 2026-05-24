import Foundation
import Capacitor

@objc(LocalNetworkPlugin)
public class LocalNetworkPlugin: CAPPlugin {
    
    @objc func requestPermission(_ call: CAPPluginCall) {
        LocalNetworkAuthorization.trigger()
        call.resolve()
    }
}
