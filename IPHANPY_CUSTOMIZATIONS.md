# iPhanpy Customizations

This document tracks all customizations made to the Phanpy codebase for the iPhanpy fork.

## Organization

All customizations are now organized in the `src/iphanpy-overrides/` folder for easier maintenance and merging from upstream.

## File Structure

```
src/iphanpy-overrides/
├── README.md                           # Documentation for the overrides folder
├── components/
│   ├── camera-capture-input.jsx        # Native camera support
│   ├── iphanpy-settings.jsx            # "iPhanpy" section in Settings (native only)
│   └── native-tab-bar.jsx              # Mirrors the web tab bar as a native tab bar
├── locales/
│   └── {locale}.po                     # Translations for iPhanpy-only strings
├── styles/
│   └── overrides.css                   # UI customizations
└── utils/
    ├── auth-overrides.js               # OAuth redirect URI + in-app auth browser
    ├── disable-input-zoom.js           # Stops WebKit zooming into small inputs
    ├── NativeTabBarPlugin.js           # JS side of the native tab bar plugin
    ├── open-link.js                    # In-app browser link interceptor
    └── status-bar-scroll.js            # iOS status bar tap → scroll to top
```

## Modified Upstream Files

The following upstream files import from `iphanpy-overrides/`:

### 1. `src/app.jsx`
- Imports CSS overrides: `./iphanpy-overrides/styles/overrides.css`
- Imports link interceptor: `./iphanpy-overrides/utils/open-link`
- Imports status bar scroll: `./iphanpy-overrides/utils/status-bar-scroll`
- Imports input zoom fix: `./iphanpy-overrides/utils/disable-input-zoom` (called next to `setupStatusBarScroll()`)
- Contains OAuth handling code for native apps (deep links, browser overlay)

### 2. `src/utils/auth.js`
- Imports redirect URI function: `../iphanpy-overrides/utils/auth-overrides`
- Uses `getRedirectURI()` instead of inline logic

### 3. `src/components/compose.jsx`
- Imports camera component: `../iphanpy-overrides/components/camera-capture-input`
- Upstream opens the camera via `cameraCaptureInputRef.current?.click()`, so the override component must accept a `ref` prop and forward it to the element it renders

### 4. `src/pages/login.jsx`
- Imports `openAuthBrowser()` from `../iphanpy-overrides/utils/auth-overrides` to open OAuth in the in-app browser
  - Narrow screens use `presentationStyle: 'popover'` (iOS shows it as a bottom sheet)
  - Wide screens (≥600px: iPad, unfolded foldables) use `'fullscreen'`, because SFSafariViewController renders blank inside a real floating popover
- Uses `store.local` instead of `sessionCookie` for code verifier (native compatibility)

### 5. `src/pages/settings.jsx`
- Imports `IphanpySettings` from `../iphanpy-overrides/components/iphanpy-settings` and renders it just above the Wellbeing section
- The component renders nothing on web, and shows whether or not the user is logged in

### 6. `src/components/shortcuts.jsx`
- Imports `NativeTabBarBridge` from `../iphanpy-overrides/components/native-tab-bar` and renders it next to the tab bar `<nav>`, passing `formattedShortcuts` and `tabBarRef`

### 7. `src/utils/safe-bounding-box-padding.js`
- Adds `iphanpyMenuInsetBottom()`, which raises the bottom padding of menus to `--iphanpy-menu-inset-bottom` so they don't open under the native tab bar

### 8. `src/utils/lang.js`
- Imports the iPhanpy catalog (`../iphanpy-overrides/locales/{locale}.po`) and merges it with the main one
- In `activateLang()`, both catalogs must be passed to `loadAndActivate()` in a single merged object. `loadAndActivate()` replaces the locale's messages, so loading the iPhanpy catalog separately gets wiped out and shows message IDs (e.g. `p44JcH`)
- The iPhanpy catalog is merged first (`{ ...iphanpyMessages, ...messages }`), so upstream wins if both have the same id: an iPhanpy entry can never replace an upstream translation with English

### 9. `lingui.config.js`
- Adds a second catalog for `src/iphanpy-overrides/`, and excludes that folder from the main catalog

## Customization Details

### Native App Support (Capacitor)

**Purpose:** Enable iPhanpy to run as a native iOS app using Capacitor

**Key Changes:**
1. **OAuth Flow** - Modified to use custom URL scheme for redirect
2. **Link Handling** - External links open in in-app browser
3. **Camera Access** - Native camera API for photo capture
4. **Deep Links** - Handle OAuth callbacks via app URL scheme

### UI Customizations

**Purpose:** Improve visual appearance and iOS compatibility

**Key Changes:**
1. **Header Blur Effect** - Frosted glass appearance on deck header
2. **Safe Area Insets** - Proper spacing for iOS notch and home indicator, plus left/right insets for devices with a side status bar (e.g. folded foldables). Upstream doesn't pad these on `.deck-container` (timelines), `.deck-backdrop` (post view) or the account sheet footer, so `overrides.css` adds them
3. **Status Bar Scroll** - Tapping iOS status bar scrolls the active timeline to top
4. **No Input Zoom** - Adds `maximum-scale=1` to the viewport on native. WebKit zooms into inputs under 16px (e.g. after reducing text size), and since Capacitor disables pinch-zoom, the app could never zoom back out (issue #10)

### iPhanpy Settings

**Purpose:** Settings that only apply to the native app, kept separate from upstream's

Saved per device with `store.local.setJSON`/`getJSON` (plain `get` returns strings, so a saved `false` reads as `"false"`, which is truthy), with keys prefixed `iphanpy-`:
- `iphanpy-openLinksExternally` (default `false`) - Opens external links in the default browser instead of the in-app browser (issue #9). On native, `window.open` is handed to the system browser by Capacitor. Login is unaffected, as it uses `openAuthBrowser()`
- `iphanpy-statusBarScroll` (default `true`) - Toggles status bar tap → scroll to top
- `iphanpy-nativeTabBar` (default `false`) - Experimental native tab bar, see below

### Translations

**Purpose:** Translate iPhanpy-only strings without touching upstream's catalogs (managed by upstream via Crowdin)

- iPhanpy strings use `<Trans>` as usual, and are extracted to `src/iphanpy-overrides/locales/{locale}.po` instead of `src/locales/`
- To add or change a string:
  1. Run `npm run messages:extract`
  2. Revert upstream catalogs with `git checkout -- src/locales`. Extracting rewrites line references across them (upstream drift), which would conflict on merge
  3. Fill in the `msgstr` for each locale in `src/iphanpy-overrides/locales/`
- Use `npx lingui extract --clean` instead to drop strings that were removed (then revert `src/locales` again)
- `npm run build` also runs `messages:extract:clean`, which renumbers references in `src/locales/en.po`. Revert it before committing

### Native Tab Bar (experimental)

**Purpose:** Replace the web tab bar with a native tab bar (Liquid Glass on iOS 26+, and the vertical bar on devices that have one, e.g. iPhone Duo)

- Enabled with the `iphanpy-nativeTabBar` setting, and only applies when the shortcuts view mode is "Tab bar" and Phanpy shows that bar at the bottom (`BOTTOM_TAB_BAR_QUERY`, copied from `shortcuts.css`; wide screens with a pointer get Phanpy's top bar instead)
- `ios/App/App/NativeTabBarPlugin.swift` adds a `UITabBarController` with empty placeholder tabs over the web view (the web view stays the only content). Using the system controller rather than a standalone `UITabBar` is what lets iOS place the bar: a standalone bar can't go vertical. Methods: `setTabs({ tabs, selected, moreCancelTitle })`, `setSelected`, `setHidden`, `setTint({ color: '#rrggbb' })`, `setTheme({ theme })`, `setScrolledAway({ away })`, `remove`. Events: `tabSelect` (tab index) and `heightChange` (how much of the bottom the bar covers, incl. the home indicator)
- Placement follows `UITraitCollection.verticalBarEdge` (iOS 27.1+, updated through `systemTraitsAffectingVerticalBarEdge`):
  - Bottom: the controller's view is a strip along the bottom, resized to the bar's height, so the rest of the web view stays touchable. Its horizontal size class is overridden to compact, as iPad's regular width would put the bar at the top
  - Leading/trailing (vertical bar): the controller's view fills the column the system reserves as safe area. `heightChange` then sends just the bottom safe area, so the compose button keeps clear of the home indicator, and hide-on-scroll slides it sideways
  - A tab bar controller always has a selected tab, so pages without a matching tab keep the last one selected
- Each tab: `{ title, symbol, image?, badge? }`
  - `image`: URL drawn as a round icon instead of the symbol (the Profile avatar, from the shortcut's `altIcon`)
  - `badge`: uses the symbol's `.badge` variant (e.g. `bell.badge`), a small dot in the icon's own color; falls back to a red badge dot if there isn't one (Notifications, when `states.notificationsShowNew`)
  - Titles are trimmed with "…" to an equal share of the bar width (`fitTitles`, capped at 440pt as iPad's bar doesn't span the screen), since iOS 26 sizes tabs to their titles and ignores `itemWidth`. The vertical bar shows no titles
- More than 5 tabs: the first 4 are shown plus the system "More" tab, which opens an action sheet with the rest (selecting one of those highlights More). On iPad and the iPhone Duo the sheet is a popover from the More tab, found through `itemViews()` (the buttons aren't exposed, so it collects the visible `UIControl`s in the tab controller's view, deduped by position as iOS 26 draws each button twice; the vertical bar's buttons aren't inside `tabBar`). The system "More" list isn't used: at most 5 placeholder tabs are given to the controller
- Titles that are promises (list names) are resolved before being sent, like the web bar's `<AsyncText>`
- "Cancel" uses upstream's translation by message id (`i18n._(id)` through a variable). An inline `i18n._({ id, message })` would be extracted into iPhanpy's catalog with an English fallback
- No long-press actions (the web bar's Profile → accounts and Lists menu): iOS 26's press-and-drag between tabs takes the touch, and the feature was dropped
- `native-tab-bar.jsx` keeps the web tab bar in the DOM but invisible (`body.iphanpy-native-tab-bar`), so spacing, the active tab and click handlers are reused: a native tap just clicks the matching web link, and the active tab is read from its `.is-active` class
- Phanpy icon names are mapped to SF Symbols in `SYMBOLS` (`.fill` variants are used for the selected tab when they exist, unknown symbols fall back to a circle)
- The native bar sits above all web content, so it is hidden while any `states.show*` flag is set or a `.deck-backdrop` (post view) is open.
- Web menus can't appear above the native bar, so they keep clear of it: `--iphanpy-menu-inset-bottom` on `:root` holds the bar height (0 while hidden), and `safeBoundingBoxPadding()` uses it as the bottom inset. Menus compute this on render, so a `resize` event is fired when the height changes (`Menu2` re-renders on resize)
- The selected tab uses Phanpy's accent (`--link-color`, resolved to hex through a canvas), resent on navigation, sheet changes and system theme changes
- The bar height is set as `--iphanpy-tab-bar-height` on `:root`; `overrides.css` uses it to place the compose button and the minimized composer (upstream assumes the web bar's `52px` + safe area)
- The bar follows Phanpy's theme setting (`store.local` `theme`: `light`, `dark`, or unset for the system) through `overrideUserInterfaceStyle`
- Hide on scroll: Phanpy slides its tab bar away while the timeline header is `hidden` (upstream CSS in `shortcuts.css`). That rule also sets `pointer-events: none`, so the bridge reads that from the (invisible) web bar instead of copying the selectors, and slides the native bar off its edge with `setScrolledAway`. It's checked when any `hidden` attribute changes (`MutationObserver`) and on navigation. Kept separate from `setHidden` (fade, for sheets) so both can apply

### App Language in iOS Settings

`Info.plist` lists the supported languages in `CFBundleLocalizations`, so iOS shows Settings → Apps → iPhanpy → Language. The web view then reports that language, and Phanpy detects it on first launch (a language picked in Phanpy's own Settings still takes priority).

- Codes are iOS-style (`de`, `pt-BR`, `zh-Hans`); Phanpy's locale matcher maps them to its own (`de-DE`, `zh-CN`)
- Keep the list in sync with the listed locales in `src/data/catalogs.json` when upstream adds a language

## Merging from Upstream

When pulling changes from upstream Phanpy:

1. **Check these files for conflicts:**
   - `src/app.jsx` (OAuth handling, link interceptor setup)
   - `src/utils/auth.js` (redirect URI import)
   - `src/components/compose.jsx` (camera component import)
   - `src/pages/login.jsx` (browser open, storage usage)
   - `src/pages/settings.jsx` (iPhanpy settings section)
   - `src/components/shortcuts.jsx` (native tab bar bridge)
   - `src/utils/safe-bounding-box-padding.js` (menu inset for the native tab bar)
   - `src/utils/lang.js` (iPhanpy catalog loading)
   - `lingui.config.js` (iPhanpy catalog)
   - `src/locales/*.po` (keep upstream's version; never commit iPhanpy changes here)

2. **Review if upstream changes affect:**
   - OAuth flow
   - Link handling
   - Media upload flow
   - Header/navigation structure

3. **Test after merge:**
   - OAuth login on web and native
   - External link opening
   - Camera capture
   - UI appearance (header blur, safe areas)
   - Status bar tap scroll to top (iOS native)
   - iPhanpy settings and their translations (switch language in Settings, check for message IDs like `p44JcH`)
   - Native tab bar (if enabled): tapping tabs, re-tapping to scroll to top, hidden under sheets and the post view
   - New languages in `src/data/catalogs.json` (add them to `CFBundleLocalizations`)

## Build Verification

Run `npm run build` to verify all imports are correct and the build succeeds.

Requires Node `>=22.19` (upstream `engines`). On older Node, npm silently skips Lingui's native binding and the build fails with "Cannot find native binding". Note that production builds strip `console.*` calls, so errors won't show in Safari Web Inspector.

## iOS Native Project (Capacitor 8.5)

- Uses the UIScene lifecycle (required by Xcode 27): `ios/App/App/SceneDelegate.swift` creates `MyViewController` as the root view controller, with `UIApplicationSceneManifest` in `Info.plist` and `configurationForConnecting` in `AppDelegate.swift`
- URL opens (OAuth callback via `iphanpy://`) are delivered to `SceneDelegate`, not the `AppDelegate` URL methods
- Local plugins are registered in `MyViewController.capacitorDidLoad()` via `registerPluginInstance` (`NativeTabBarPlugin`), or with a `.m` `CAP_PLUGIN` file (`LocalNetworkPlugin`). New Swift files must be added to the Xcode project
- iOS deployment target is 15.0 (Podfile and Xcode project)

## Additional Customization Files

These files are specific to iPhanpy and don't exist in upstream Phanpy:

- **`capacitor.config.json`** - Capacitor configuration for native app
- **`package.json`** - Added `@capacitor/*` dependencies (camera, browser, app, core)
- **`iPhanpy icon.icon/`** - Custom app icon with Liquid Glass style support
- **`ios/`** - iOS native app files and XCode project
- **`altstore/`** - AltStore distribution files
