import { Capacitor } from '@capacitor/core';

/**
 * iOS Status Bar Tap → Scroll to Top
 *
 * Tapping the iOS status bar area scrolls the visible .deck-container to top.
 */
export function setupStatusBarScroll() {
  if (!Capacitor.isNativePlatform()) return;

  window.addEventListener('statusTap', () => {
    const container = document.querySelector(
      '.deck-container:not([hidden])',
    );
    if (container) {
      container.scrollTo({ top: 0, behavior: 'smooth' });
    }
  });
}
