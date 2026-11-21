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
        CAPPluginMethod(name: "setTheme", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setScrolledAway", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remove", returnType: CAPPluginReturnPromise),
    ]

    /// Like UITabBarController: with more tabs than this, the last spot becomes "More"
    private static let maxVisibleTabs = 5
    private static let moreTag = -1

    private var tabBar: UITabBar?
    private var heightObservation: NSKeyValueObservation?
    /// Tabs behind "More", shown in an action sheet
    private var overflow: [(index: Int, title: String)] = []
    private var moreCancelTitle = "Cancel"
    private var selectedIndex: Int?
    private var imageCache: [String: UIImage] = [:]

    @objc func setTabs(_ call: CAPPluginCall) {
        let tabs = call.getArray("tabs", JSObject.self) ?? []
        let selected = call.getInt("selected")
        let cancelTitle = call.getString("moreCancelTitle")
        DispatchQueue.main.async {
            guard let bar = self.tabBar ?? self.makeTabBar() else {
                call.reject("No view to attach the tab bar to")
                return
            }
            let visibleCount = tabs.count > Self.maxVisibleTabs ? Self.maxVisibleTabs - 1 : tabs.count
            var items = tabs.prefix(visibleCount).enumerated().map { index, tab in
                self.makeItem(tab, index: index)
            }
            self.overflow = tabs.enumerated().dropFirst(visibleCount).map {
                (index: $0.offset, title: $0.element["title"] as? String ?? "")
            }
            if !self.overflow.isEmpty {
                items.append(UITabBarItem(tabBarSystemItem: .more, tag: Self.moreTag))
            }
            if let cancelTitle { self.moreCancelTitle = cancelTitle }
            bar.items = items
            self.fitTitles(in: bar)
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

    /// Phanpy's theme setting: "light", "dark", or anything else to follow the system
    @objc func setTheme(_ call: CAPPluginCall) {
        let theme = call.getString("theme")
        DispatchQueue.main.async {
            self.tabBar?.overrideUserInterfaceStyle =
                theme == "light" ? .light : theme == "dark" ? .dark : .unspecified
            call.resolve()
        }
    }

    /// Slides the bar off screen while scrolling down, like the web tab bar.
    /// Separate from setHidden (sheets), so both can apply at once.
    @objc func setScrolledAway(_ call: CAPPluginCall) {
        let away = call.getBool("away") ?? false
        DispatchQueue.main.async {
            guard let bar = self.tabBar else {
                call.resolve()
                return
            }
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                bar.transform = away ? CGAffineTransform(translationX: 0, y: bar.bounds.height) : .identity
            }
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
        if item.tag == Self.moreTag {
            presentMore()
        } else {
            notifyListeners("tabSelect", data: ["index": item.tag])
        }
    }

    /// Tab `index` from the web side; tabs behind "More" select the More tab
    private func select(_ index: Int?) {
        guard let bar = tabBar else { return }
        selectedIndex = index
        let tag = index.map { i in overflow.contains { $0.index == i } ? Self.moreTag : i }
        bar.selectedItem = tag.flatMap { t in bar.items?.first { $0.tag == t } }
    }

    private func makeItem(_ tab: JSObject, index: Int) -> UITabBarItem {
        var symbol = tab["symbol"] as? String ?? "circle"
        let badge = tab["badge"] as? Bool == true
        // Prefer the symbol's own badge variant (e.g. bell.badge): a small dot in the icon's color
        let hasBadgeSymbol = badge && UIImage(systemName: "\(symbol).badge") != nil
        if hasBadgeSymbol { symbol += ".badge" }
        let image = UIImage(systemName: symbol) ?? UIImage(systemName: "circle")
        let item = UITabBarItem(
            title: tab["title"] as? String,
            image: image,
            selectedImage: UIImage(systemName: "\(symbol).fill") ?? image
        )
        item.tag = index
        // Otherwise an empty badge shows as a (red) dot
        item.badgeValue = badge && !hasBadgeSymbol ? "" : nil
        if let url = tab["image"] as? String {
            loadImage(url) { [weak item] image in
                item?.image = image
                item?.selectedImage = image
            }
        }
        return item
    }

    /// iOS 26 sizes tabs to their titles (itemWidth is ignored), so a long title like
    /// "Benachrichtigungen" makes its tab wider. Trim titles to an equal share of the bar.
    /// shortcut: fitted to the width at setTabs time, refit on rotation if it looks off in landscape
    private func fitTitles(in bar: UITabBar) {
        guard let items = bar.items, !items.isEmpty else { return }
        bar.layoutIfNeeded()
        var labels: [UILabel] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                if let label = subview as? UILabel { labels.append(label) } else { walk(subview) }
            }
        }
        walk(bar)
        let font = labels.first?.font ?? .systemFont(ofSize: 10, weight: .medium)
        // The glass capsule is inset from the screen edges, and tabs need some padding
        let maxWidth = (bar.bounds.width - 64) / CGFloat(items.count) - 12
        for item in items {
            guard var title = item.title, !title.isEmpty else { continue }
            let fits = { (text: String) in (text as NSString).size(withAttributes: [.font: font]).width <= maxWidth }
            guard !fits(title) else { continue }
            while title.count > 1 && !fits(title + "…") { title.removeLast() }
            item.title = title + "…"
        }
    }

    // MARK: - More

    private func presentMore() {
        guard let bar = tabBar, let presenter = bridge?.viewController else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for tab in overflow {
            sheet.addAction(UIAlertAction(title: tab.title, style: .default) { [weak self] _ in
                self?.notifyListeners("tabSelect", data: ["index": tab.index])
            })
        }
        sheet.addAction(UIAlertAction(title: moreCancelTitle, style: .cancel) { [weak self] _ in
            // Put the selection back on the current tab
            self?.select(self?.selectedIndex)
        })
        // iPad shows it as a popover from the More tab
        if let popover = sheet.popoverPresentationController {
            let views = itemViews(in: bar)
            popover.sourceView = views.count == bar.items?.count ? views.last : bar
            popover.sourceRect = popover.sourceView?.bounds ?? bar.bounds
        }
        presenter.present(sheet, animated: true)
    }

    // MARK: - Images

    /// Loads an image (e.g. the profile avatar) as a round tab icon
    private func loadImage(_ urlString: String, completion: @escaping (UIImage) -> Void) {
        if let cached = imageCache[urlString] { return completion(cached) }
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let source = UIImage(data: data) else { return }
            let size = CGSize(width: 28, height: 28)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
                source.draw(in: CGRect(origin: .zero, size: size))
            }.withRenderingMode(.alwaysOriginal)
            DispatchQueue.main.async {
                self.imageCache[urlString] = image
                completion(image)
            }
        }.resume()
    }

    /// The tab buttons, left to right. UITabBar doesn't expose them, so this looks for its
    /// UIControls; iOS 26 draws each button twice (normal and selected layers) at the same spot.
    private func itemViews(in bar: UITabBar) -> [UIView] {
        var controls: [UIView] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                if subview is UIControl { controls.append(subview) } else { walk(subview) }
            }
        }
        walk(bar)
        let midX = { (view: UIView) in view.convert(view.bounds, to: bar).midX }
        var seen = Set<Int>()
        return controls
            .filter { seen.insert(Int(midX($0).rounded())).inserted }
            .sorted { midX($0) < midX($1) }
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
