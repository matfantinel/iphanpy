import { Browser } from '@capacitor/browser';
import { Capacitor } from '@capacitor/core';

/**
 * Opens a URL in the in-app browser on native platforms,
 * or in a new tab on web.
 */
export async function openLink(url) {
  if (!url) return;

  const isNative = Capacitor.isNativePlatform();

  if (isNative) {
    try {
      await Browser.open({ url });
    } catch (error) {
      console.error('Failed to open link:', error);
      // Fallback to window.open
      window.open(url, '_blank');
    }
  } else {
    window.open(url, '_blank');
  }
}

/**
 * Intercepts clicks on external links and opens them in the in-app browser
 */
export function setupLinkInterceptor() {
  if (!Capacitor.isNativePlatform()) return;

  document.addEventListener(
    'click',
    (e) => {
      // Find the closest anchor tag
      const anchor = e.target.closest('a[href]');
      if (!anchor) return;

      // Only intercept links with target="_blank"
      if (anchor.getAttribute('target') !== '_blank') return;

      const href = anchor.getAttribute('href');
      if (!href) return;

      // Only intercept external links (http/https)
      if (!/^https?:\/\//i.test(href)) return;

      // Check if it's an internal link (same origin)
      try {
        const url = new URL(href);
        if (url.origin === window.location.origin) return;
      } catch (e) {
        return;
      }

      // Prevent default and open in in-app browser
      e.preventDefault();
      e.stopPropagation();
      openLink(href);
    },
    true, // Use capture phase
  );
}
