import { Capacitor } from '@capacitor/core';
import { useEffect, useRef, useState } from 'preact/hooks';
import { useLocation } from 'react-router-dom';
import { useSnapshot } from 'valtio';

import states from '../../utils/states';
import store from '../../utils/store';
import NativeTabBar from '../utils/NativeTabBarPlugin';

export const NATIVE_TAB_BAR_EVENT = 'iphanpy-nativeTabBar';

// shortcut: more tabs fall back to the web tab bar, until there's a "More" tab
const MAX_TABS = 5;

// Phanpy icon name → SF Symbol (".fill" is added for the selected tab when it exists)
const SYMBOLS = {
  home: 'house',
  at: 'at',
  notification: 'bell',
  list: 'list.bullet',
  building: 'building.2',
  earth: 'globe',
  chart: 'chart.line.uptrend.xyaxis',
  search: 'magnifyingglass',
  user: 'person.crop.circle',
  bookmark: 'bookmark',
  heart: 'heart',
  history2: 'clock.arrow.circlepath',
  hashtag: 'number',
};

// Resolves Phanpy's accent (--link-color, any CSS color) to #rrggbb for the native side
function getAccentHex() {
  const probe = document.createElement('span');
  probe.style.color = 'var(--link-color)';
  document.body.append(probe);
  const color = getComputedStyle(probe).color;
  probe.remove();
  const ctx = document.createElement('canvas').getContext('2d');
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return '#' + [r, g, b].map((v) => v.toString(16).padStart(2, '0')).join('');
}

function useNativeTabBarSetting() {
  const get = () =>
    Capacitor.isNativePlatform() &&
    !!store.local.getJSON('iphanpy-nativeTabBar');
  const [enabled, setEnabled] = useState(get);
  useEffect(() => {
    const update = () => setEnabled(get());
    window.addEventListener(NATIVE_TAB_BAR_EVENT, update);
    return () => window.removeEventListener(NATIVE_TAB_BAR_EVENT, update);
  }, []);
  return enabled;
}

/**
 * Mirrors the web tab bar (`tabBarRef`) as a native UITabBar.
 * The web tab bar stays in the DOM (invisible) so its spacing, active state
 * and click handlers keep working: native taps just click the matching link.
 */
function NativeTabBarBridge({ shortcuts, tabBarRef }) {
  const enabled = useNativeTabBarSetting();
  const active = enabled && shortcuts.length <= MAX_TABS;
  const location = useLocation();
  const snapStates = useSnapshot(states);
  // Bar height and visibility, for keeping web menus clear of the bar
  const heightRef = useRef(0);
  const hiddenRef = useRef(false);
  const syncMenuInset = () =>
    document.documentElement.style.setProperty(
      '--iphanpy-menu-inset-bottom',
      `${hiddenRef.current ? 0 : heightRef.current}px`,
    );

  // shortcut: titles that aren't plain strings (e.g. async list names) show empty, until phase 2
  const tabs = shortcuts.map(({ icon, title }) => ({
    title: typeof title === 'string' ? title : '',
    symbol: SYMBOLS[icon] || 'circle',
  }));
  const tabsKey = JSON.stringify(tabs);

  // Read the active tab from the web links, so it matches Phanpy's own logic
  const getSelected = () => {
    const links = tabBarRef.current?.querySelectorAll(':scope > ul > li > a');
    const index = [...(links || [])].findIndex((a) =>
      a.classList.contains('is-active'),
    );
    return index === -1 ? undefined : index;
  };

  useEffect(() => {
    document.body.classList.toggle('iphanpy-native-tab-bar', active);
    if (!active) return;
    NativeTabBar.setTabs({ tabs, selected: getSelected() });
  }, [active, tabsKey]);

  useEffect(() => {
    if (!active) return;
    return () => {
      document.body.classList.remove('iphanpy-native-tab-bar');
      NativeTabBar.remove();
    };
  }, [active]);

  useEffect(() => {
    if (!active) return;
    const handle = NativeTabBar.addListener('tabSelect', ({ index }) => {
      tabBarRef.current
        ?.querySelectorAll(':scope > ul > li > a')
        [index]?.click();
    });
    const heightHandle = NativeTabBar.addListener(
      'heightChange',
      ({ height }) => {
        if (height > 0) {
          if (height !== heightRef.current) {
            heightRef.current = height;
            syncMenuInset();
            // Menus compute their padding on render; Menu2 re-renders on resize
            window.dispatchEvent(new Event('resize'));
          }
          document.documentElement.style.setProperty(
            '--iphanpy-tab-bar-height',
            `${height}px`,
          );
        }
      },
    );
    return () => {
      handle.then((h) => h.remove());
      heightHandle.then((h) => h.remove());
      document.documentElement.style.removeProperty('--iphanpy-tab-bar-height');
      document.documentElement.style.removeProperty(
        '--iphanpy-menu-inset-bottom',
      );
    };
  }, [active]);

  // Theme changes can change the accent color
  useEffect(() => {
    if (!active) return;
    const media = matchMedia('(prefers-color-scheme: dark)');
    const update = () => NativeTabBar.setTint({ color: getAccentHex() });
    media.addEventListener('change', update);
    return () => media.removeEventListener('change', update);
  }, [active]);

  // The native bar sits above all web content, so hide it under anything that
  // covers the web tab bar: modals/sheets (show* states) and the post view.
  // Web menus can't go above it, so they keep clear of it instead (see syncMenuInset)
  const modalOpen = Object.entries(snapStates).some(
    ([key, value]) => key.startsWith('show') && value,
  );

  useEffect(() => {
    if (!active) return;
    NativeTabBar.setSelected({ selected: getSelected() });
    NativeTabBar.setTint({ color: getAccentHex() });
    hiddenRef.current = modalOpen || !!document.querySelector('.deck-backdrop');
    syncMenuInset();
    NativeTabBar.setHidden({ hidden: hiddenRef.current });
  }, [active, tabsKey, location.pathname, location.search, modalOpen]);

  return null;
}

export default NativeTabBarBridge;
