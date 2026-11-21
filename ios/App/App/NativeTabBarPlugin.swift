import UIKit
import Capacitor

/// A native UITabBar laid over the web view, mirroring Phanpy's tab bar shortcuts.
/// The web side sends the tabs and selection; taps come back as `tabSelect` events.
@objc(NativeTabBarPlugin)
public class NativeTabBarPlugin: CAPPlugin, CAPBridgedPlugin, UITabBarDelegate {
    public let identifier = "NativeTabBarPlugin"
    public let jsName = "NativeTabBar"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setTabs", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setSelected", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setHidden", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTint", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remove", returnType: CAPPluginReturnPromise),
    ]

    private var tabBar: UITabBar?
    private var heightObservation: NSKeyValueObservation?

    @objc func setTabs(_ call: CAPPluginCall) {
        let tabs = call.getArray("tabs", JSObject.self) ?? []
        let selected = call.getInt("selected")
        DispatchQueue.main.async {
            guard let bar = self.tabBar ?? self.makeTabBar() else {
                call.reject("No view to attach the tab bar to")
                return
            }
            bar.items = tabs.enumerated().map { index, tab in
                let symbol = tab["symbol"] as? String ?? "circle"
                let image = UIImage(systemName: symbol) ?? UIImage(systemName: "circle")
                let item = UITabBarItem(
                    title: tab["title"] as? String,
                    image: image,
                    selectedImage: UIImage(systemName: "\(symbol).fill") ?? image
                )
                item.tag = index
                return item
            }
            self.select(selected)
            call.resolve()
        }
    }

    @objc func setSelected(_ call: CAPPluginCall) {
        let selected = call.getInt("selected")
        DispatchQueue.main.async {
            self.select(selected)
            call.resolve()
        }
    }

    @objc func setHidden(_ call: CAPPluginCall) {
        let hidden = call.getBool("hidden") ?? false
        DispatchQueue.main.async {
            guard let bar = self.tabBar else {
                call.resolve()
                return
            }
            if !hidden { bar.isHidden = false }
            UIView.animate(withDuration: 0.2, animations: {
                bar.alpha = hidden ? 0 : 1
            }, completion: { _ in
                // A later setHidden(false) may have run during the fade
                if hidden && bar.alpha == 0 { bar.isHidden = true }
            })
            call.resolve()
        }
    }

    /// Accent color for the selected tab, as `#rrggbb`
    @objc func setTint(_ call: CAPPluginCall) {
        let hex = call.getString("color") ?? ""
        DispatchQueue.main.async {
            self.tabBar?.tintColor = Self.color(hex: hex)
            call.resolve()
        }
    }

    @objc func remove(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.heightObservation = nil
            self.tabBar?.removeFromSuperview()
            self.tabBar = nil
            call.resolve()
        }
    }

    public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        notifyListeners("tabSelect", data: ["index": item.tag])
    }

    private func select(_ index: Int?) {
        guard let bar = tabBar else { return }
        bar.selectedItem = index.flatMap { i in bar.items?.first { $0.tag == i } }
    }

    private static func color(hex: String) -> UIColor? {
        guard hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private func makeTabBar() -> UITabBar? {
        guard let view = bridge?.viewController?.view else { return nil }
        let bar = UITabBar()
        bar.delegate = self
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // Report the height (incl. the home indicator area) so the web side can lay out around it
        heightObservation = bar.observe(\.bounds, options: [.initial, .new]) { [weak self] bar, _ in
            self?.notifyListeners("heightChange", data: ["height": bar.bounds.height], retainUntilConsumed: true)
        }
        tabBar = bar
        return bar
    }
}
