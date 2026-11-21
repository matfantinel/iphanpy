import { Capacitor } from '@capacitor/core';

/**
 * WebKit zooms into focused inputs under 16px, which sticks in WKWebView
 * when the text size setting is reduced (issue #10).
 */
export function disableInputZoom() {
  if (!Capacitor.isNativePlatform()) return;

  const meta = document.querySelector('meta[name="viewport"]');
  if (meta) meta.content += ', maximum-scale=1';
}
