import { Browser } from '@capacitor/browser';
import { Capacitor } from '@capacitor/core';

/**
 * iPhanpy Auth Overrides
 * 
 * Customizations for OAuth flow to support Capacitor native apps.
 * This modifies the redirect URI to use the custom URL scheme for native platforms.
 */

const {
  DEV,
  VITE_PHANPY_WEBSITE: WEBSITE,
} = import.meta.env;

/**
 * Get the appropriate redirect URI for OAuth
 * - Native apps: Use custom URL scheme
 * - Web: Use current location or WEBSITE config
 */
export function getRedirectURI() {
  const isNative = Capacitor.isNativePlatform();
  
  if (isNative) {
    return `${location.protocol}//${location.host}/`;
  }
  
  const sameSite = WEBSITE
    ? WEBSITE.toLowerCase().includes(location.hostname)
    : false;
  const currentLocation = location.origin + location.pathname;
  
  return DEV || !sameSite ? currentLocation : WEBSITE;
}

/**
 * Open the OAuth authorization URL in the in-app browser.
 * - Narrow screens (iPhone): popover, which iOS adapts into a bottom sheet
 * - Wide screens (iPad, unfolded foldables): fullscreen, because
 *   SFSafariViewController renders blank inside a real floating popover
 */
export async function openAuthBrowser(url) {
  const isWideScreen = window.matchMedia('(min-width: 600px)').matches;
  await Browser.open({
    url,
    presentationStyle: isWideScreen ? 'fullscreen' : 'popover',
  });
}
