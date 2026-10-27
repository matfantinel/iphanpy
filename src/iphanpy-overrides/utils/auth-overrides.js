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
