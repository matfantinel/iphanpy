# iPhanpy Customizations

This document tracks all customizations made to the Phanpy codebase for the iPhanpy fork.

## Organization

All customizations are now organized in the `src/iphanpy-overrides/` folder for easier maintenance and merging from upstream.

## File Structure

```
src/iphanpy-overrides/
├── README.md                           # Documentation for the overrides folder
├── components/
│   └── camera-capture-input.jsx        # Native camera support
├── styles/
│   └── overrides.css                   # UI customizations
└── utils/
    ├── auth-overrides.js               # OAuth redirect URI handling
    ├── open-link.js                    # In-app browser link interceptor
    └── status-bar-scroll.js            # iOS status bar tap → scroll to top
```

## Modified Upstream Files

The following upstream files import from `iphanpy-overrides/`:

### 1. `src/app.jsx`
- Imports CSS overrides: `./iphanpy-overrides/styles/overrides.css`
- Imports link interceptor: `./iphanpy-overrides/utils/open-link`
- Imports status bar scroll: `./iphanpy-overrides/utils/status-bar-scroll`
- Contains OAuth handling code for native apps (deep links, browser overlay)

### 2. `src/utils/auth.js`
- Imports redirect URI function: `../iphanpy-overrides/utils/auth-overrides`
- Uses `getRedirectURI()` instead of inline logic

### 3. `src/components/compose.jsx`
- Imports camera component: `../iphanpy-overrides/components/camera-capture-input`

### 4. `src/pages/login.jsx`
- Uses `@capacitor/browser` to open OAuth in in-app browser
- Uses `store.local` instead of `sessionCookie` for code verifier (native compatibility)

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
2. **Safe Area Insets** - Proper spacing for iOS notch and home indicator
3. **Status Bar Scroll** - Tapping iOS status bar scrolls the active timeline to top

## Merging from Upstream

When pulling changes from upstream Phanpy:

1. **Check these files for conflicts:**
   - `src/app.jsx` (OAuth handling, link interceptor setup)
   - `src/utils/auth.js` (redirect URI import)
   - `src/components/compose.jsx` (camera component import)
   - `src/pages/login.jsx` (browser open, storage usage)

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

## Build Verification

Run `npm run build` to verify all imports are correct and the build succeeds.

## Additional Customization Files

These files are specific to iPhanpy and don't exist in upstream Phanpy:

- **`capacitor.config.json`** - Capacitor configuration for native app
- **`package.json`** - Added `@capacitor/*` dependencies (camera, browser, app, core)
- **`iPhanpy icon.icon/`** - Custom app icon with Liquid Glass style support
- **`ios/`** - iOS native app files and XCode project
- **`altstore/`** - AltStore distribution files
