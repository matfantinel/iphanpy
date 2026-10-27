import UIKit
import WebKit
import Capacitor

class MyViewController: CAPBridgeViewController {
    override func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        let configuration = super.webViewConfiguration(for: instanceConfiguration)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        configuration.applicationNameForUserAgent = "iPhanpy/\(version) (+https://github.com/matfantinel/iphanpy)"
        return configuration
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView!.allowsBackForwardNavigationGestures = true
    }
}
