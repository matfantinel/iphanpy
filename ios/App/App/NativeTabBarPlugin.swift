import UIKit
import Capacitor

/// A native tab bar laid over the web view, mirroring Phanpy's tab bar shortcuts.
/// It's a UITabBarController with empty placeholder tabs (the web view stays the only content),
/// so the system places the bar: at the bottom, or in the vertical bar on devices that have one.
/// The web side sends the tabs and selection; taps come back as `tabSelect` events.
@objc(NativeTabBarPlugin)
public class NativeTabBarPlugin: CAPPlugin, CAPBridgedPlugin, UITabBarControllerDelegate {
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

    /// Like UITabBarController's own: with more tabs than this, the last spot becomes "More"
    private static let maxVisibleTabs = 5
    private static let moreTag = -1

    /// Where the system puts the bar: the bottom, or the vertical bar's edge
    private enum Placement { case bottom, leading, trailing }

    private var tabController: UITabBarController?
    private var placement: Placement?
    /// The container only covers the bar's area, so the rest of the web view stays touchable
    private var placementConstraints: [NSLayoutConstraint] = []
    private var stripHeight: NSLayoutConstraint?
    private var heightObservation: NSKeyValueObservation?
    private var traitRegistration: Any?
    private var tabs: [JSObject] = []
    /// Tabs behind "More", shown in an action sheet
    private var overflow: [(index: Int, title: String)] = []
    private var moreCancelTitle = "Cancel"
    private var selectedIndex: Int?
    private var scrolledAway = false
    private var imageCache: [String: UIImage] = [:]

    @objc func setTabs(_ call: CAPPluginCall) {
        let tabs = call.getArray("tabs", JSObject.self) ?? []
        let selected = call.getInt("selected")
        let cancelTitle = call.getString("moreCancelTitle")
        DispatchQueue.main.async {
            guard let tabController = self.tabController ?? self.makeTabController() else {
                call.reject("No view to attach the tab bar to")
                return
            }
            if let cancelTitle { self.moreCancelTitle = cancelTitle }
            self.tabs = tabs
            self.applyTabs(to: tabController)
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
            guard let container = self.tabController?.view else {
                call.resolve()
                return
            }
            if !hidden { container.isHidden = false }
            UIView.animate(withDuration: 0.2, animations: {
                container.alpha = hidden ? 0 : 1
            }, completion: { _ in
                // A later setHidden(false) may have run during the fade
                if hidden && container.alpha == 0 { container.isHidden = true }
            })
            call.resolve()
        }
    }

    /// Accent color for the selected tab, as `#rrggbb`
    @objc func setTint(_ call: CAPPluginCall) {
        let hex = call.getString("color") ?? ""
        DispatchQueue.main.async {
            // On the container, as the vertical bar's buttons don't follow the tab bar's tint
            self.tabController?.view.tintColor = Self.color(hex: hex)
            call.resolve()
        }
    }

    /// Phanpy's theme setting: "light", "dark", or anything else to follow the system
    @objc func setTheme(_ call: CAPPluginCall) {
        let theme = call.getString("theme")
        DispatchQueue.main.async {
            self.tabController?.overrideUserInterfaceStyle =
                theme == "light" ? .light : theme == "dark" ? .dark : .unspecified
            call.resolve()
        }
    }

    /// Slides the bar off screen while scrolling down, like the web tab bar.
    /// Separate from setHidden (sheets), so both can apply at once.
    @objc func setScrolledAway(_ call: CAPPluginCall) {
        let away = call.getBool("away") ?? false
        DispatchQueue.main.async {
            self.scrolledAway = away
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                self.applyScrolledAway()
            }
            call.resolve()
        }
    }

    @objc func remove(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.heightObservation = nil
            if #available(iOS 17.0, *), let registration = self.traitRegistration as? UITraitChangeRegistration {
                self.bridge?.viewController?.unregisterForTraitChanges(registration)
            }
            self.traitRegistration = nil
            if let tabController = self.tabController {
                tabController.willMove(toParent: nil)
                tabController.view.removeFromSuperview()
                tabController.removeFromParent()
            }
            self.tabController = nil
            self.placement = nil
            self.placementConstraints = []
            call.resolve()
        }
    }

    public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        let tag = viewController.tabBarItem.tag
        if tag == Self.moreTag {
            presentMore()
        } else {
            notifyListeners("tabSelect", data: ["index": tag])
        }
    }

    /// Tab `index` from the web side; tabs behind "More" select the More tab.
    /// A tab bar controller always has a selected tab, so pages without one keep the last.
    private func select(_ index: Int?) {
        guard let tabController else { return }
        selectedIndex = index
        guard let index else { return }
        let tag = overflow.contains { $0.index == index } ? Self.moreTag : index
        if let position = tabController.viewControllers?.firstIndex(where: { $0.tabBarItem.tag == tag }) {
            tabController.selectedIndex = position
        }
    }

    private func applyTabs(to tabController: UITabBarController) {
        let visibleCount = tabs.count > Self.maxVisibleTabs ? Self.maxVisibleTabs - 1 : tabs.count
        var items = tabs.prefix(visibleCount).enumerated().map { index, tab in
            makeItem(tab, index: index)
        }
        overflow = tabs.enumerated().dropFirst(visibleCount).map {
            (index: $0.offset, title: $0.element["title"] as? String ?? "")
        }
        if !overflow.isEmpty {
            items.append(UITabBarItem(tabBarSystemItem: .more, tag: Self.moreTag))
        }
        tabController.setViewControllers(items.map { item in
            let placeholder = UIViewController()
            placeholder.view.backgroundColor = .clear
            placeholder.tabBarItem = item
            return placeholder
        }, animated: false)
        // The vertical bar doesn't show titles
        if placement == .bottom { fitTitles(in: tabController.tabBar) }    }

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
        bar.superview?.layoutIfNeeded()
        bar.layoutIfNeeded()
        var labels: [UILabel] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                if let label = subview as? UILabel { labels.append(label) } else { walk(subview) }
            }
        }
        walk(bar)
        let font = labels.first?.font ?? .systemFont(ofSize: 10, weight: .medium)
        // The glass capsule is inset from the screen edges, and tabs need some padding.
        // shortcut: iPad's capsule doesn't span the screen, 440pt is about its width with 5 tabs
        let maxWidth = (min(bar.bounds.width, 440) - 64) / CGFloat(items.count) - 12
        for item in items {
            guard var title = item.title, !title.isEmpty else { continue }
            let fits = { (text: String) in (text as NSString).size(withAttributes: [.font: font]).width <= maxWidth }
            guard !fits(title) else { continue }
            while title.count > 1 && !fits(title + "…") { title.removeLast() }
            item.title = title + "…"
        }
    }

    // MARK: - Placement

    private func makeTabController() -> UITabBarController? {
        guard let parent = bridge?.viewController, let view = parent.view else { return nil }
        let tabController = UITabBarController()
        tabController.delegate = self
        parent.addChild(tabController)
        tabController.view.backgroundColor = .clear
        tabController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabController.view)
        tabController.didMove(toParent: parent)
        self.tabController = tabController

        // The bar's height doesn't depend on the container's, so the strip is resized to fit it.
        // Reported (incl. the home indicator area) so the web side can lay out around it.
        heightObservation = tabController.tabBar.observe(\.bounds, options: [.new]) { [weak self] _, _ in
            self?.reportHeight()
        }
        if #available(iOS 27.1, *) {
            traitRegistration = parent.registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
                [weak self] (_: UIViewController, _: UITraitCollection) in
                self?.updatePlacement()
            }
        }
        updatePlacement()
        return tabController
    }

    /// Follows the system's vertical bar (e.g. iPhone Duo), and the bottom everywhere else
    private func updatePlacement() {
        guard let tabController, let parent = bridge?.viewController, let view = parent.view else { return }
        var newPlacement = Placement.bottom
        if #available(iOS 27.1, *) {
            switch parent.traitCollection.verticalBarEdge {
            case .leading: newPlacement = .leading
            case .trailing: newPlacement = .trailing
            default: break
            }
        }
        guard newPlacement != placement else { return }
        placement = newPlacement

        let container = tabController.view!
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.deactivate(placementConstraints)
        switch newPlacement {
        case .bottom:
            let height = container.heightAnchor.constraint(equalToConstant: stripHeight?.constant ?? 100)
            stripHeight = height
            placementConstraints = [
                container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                height,
            ]
        case .leading, .trailing:
            // The system reserves the vertical bar's column as safe area
            let leading = newPlacement == .leading
            placementConstraints = [
                container.topAnchor.constraint(equalTo: view.topAnchor),
                container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                leading
                    ? container.leadingAnchor.constraint(equalTo: view.leadingAnchor)
                    : container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                leading
                    ? container.trailingAnchor.constraint(equalTo: safeArea.leadingAnchor)
                    : container.leadingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            ]
        }
        NSLayoutConstraint.activate(placementConstraints)
        // On iPad (regular width) UITabBarController puts its bar at the top; keep it at the bottom
        parent.setOverrideTraitCollection(
            newPlacement == .bottom ? UITraitCollection(horizontalSizeClass: .compact) : nil,
            forChild: tabController
        )
        // Titles are trimmed for the bottom bar only
        if !tabs.isEmpty {
            applyTabs(to: tabController)
            select(selectedIndex)
        }
        applyScrolledAway()
        view.layoutIfNeeded()
        reportHeight()
    }

    /// How much of the bottom the bar covers (incl. the home indicator area), so the web side can lay out around it
    private func reportHeight() {
        guard let placement, let bar = tabController?.tabBar, let view = bridge?.viewController?.view else { return }
        guard placement == .bottom else {
            // Nothing covers the bottom then, but web content should still keep clear of the home indicator
            notifyListeners("heightChange", data: ["height": view.safeAreaInsets.bottom], retainUntilConsumed: true)
            return
        }
        let height = bar.frame.height
        guard height > 0 else { return }
        if stripHeight?.constant != height { stripHeight?.constant = height }
        notifyListeners("heightChange", data: ["height": height], retainUntilConsumed: true)
    }

    /// Moves the bar off its edge when scrolled away
    private func applyScrolledAway() {
        guard let container = tabController?.view else { return }
        guard scrolledAway else {
            container.transform = .identity
            return
        }
        switch placement {
        case .leading: container.transform = CGAffineTransform(translationX: -container.bounds.width, y: 0)
        case .trailing: container.transform = CGAffineTransform(translationX: container.bounds.width, y: 0)
        default: container.transform = CGAffineTransform(translationX: 0, y: container.bounds.height)
        }
    }

    // MARK: - More

    private func presentMore() {
        guard let tabController, let presenter = bridge?.viewController else { return }
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
        // iPad and the iPhone Duo show it as a popover from the More tab
        if let popover = sheet.popoverPresentationController {
            let views = itemViews(in: tabController.view)
            popover.sourceView = views.count == tabController.viewControllers?.count ? views.last : tabController.tabBar
            popover.sourceRect = popover.sourceView?.bounds ?? .zero
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

    /// The tab buttons, in order (left to right, or top to bottom on the vertical bar).
    /// They aren't exposed, so this looks for visible UIControls (the vertical bar's are
    /// outside `tabBar`); iOS 26 draws each button twice (normal and selected layers) at the same spot.
    private func itemViews(in container: UIView) -> [UIView] {
        var controls: [UIView] = []
        func walk(_ view: UIView) {
            for subview in view.subviews where !subview.isHidden && subview.alpha > 0 {
                if subview is UIControl { controls.append(subview) } else { walk(subview) }
            }
        }
        walk(container)
        let center = { (view: UIView) in view.convert(view.bounds, to: container) }
        let position = { (view: UIView) in center(view).midX + center(view).midY }
        var seen = Set<String>()
        return controls
            .filter { seen.insert("\(Int(center($0).midX.rounded())),\(Int(center($0).midY.rounded()))").inserted }
            .sorted { position($0) < position($1) }
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
}
