import { Capacitor } from '@capacitor/core';
import { useEffect, useRef, useState } from 'preact/hooks';
import { useLingui } from '@lingui/react';
import { useLocation } from 'react-router-dom';
import { useSnapshot } from 'valtio';

import states from '../../utils/states';
import store from '../../utils/store';
import NativeTabBar from '../utils/NativeTabBarPlugin';

export const NATIVE_TAB_BAR_EVENT = 'iphanpy-nativeTabBar';

// Upstream's "Cancel" message id, so it uses upstream's translations. Passed as a
// variable, as Lingui would extract an inline descriptor into iPhanpy's catalog
const CANCEL_MESSAGE = 'dEgA5A';

// Where Phanpy shows its tab bar at the bottom (from shortcuts.css). Elsewhere
// (wide screens with a pointer) it's at the top, so the native bar isn't used
const BOTTOM_TAB_BAR_QUERY =
  '(max-width: calc(40em - 1px)), (min-width: 40em) and (hover: none)';

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

function useMediaQuery(query) {
  const [matches, setMatches] = useState(() => matchMedia(query).matches);
  useEffect(() => {
    const media = matchMedia(query);
    const update = () => setMatches(media.matches);
    media.addEventListener('change', update);
    return () => media.removeEventListener('change', update);
  }, [query]);
  return matches;
}

/**
 * Mirrors the web tab bar (`tabBarRef`) as a native UITabBar.
 * The web tab bar stays in the DOM (invisible) so its spacing, active state
 * and click handlers keep working: native taps just click the matching link.
 */
function NativeTabBarBridge({ shortcuts, tabBarRef }) {
  const enabled = useNativeTabBarSetting();
  const active = useMediaQuery(BOTTOM_TAB_BAR_QUERY) && enabled;
  const location = useLocation();
  const snapStates = useSnapshot(states);
  // Bar height and visibility, for keeping web menus clear of the bar
  const heightRef = useRef(0);
  const hiddenRef = useRef(false);
  const awayRef = useRef(false);
  const syncMenuInset = () =>
    document.documentElement.style.setProperty(
      '--iphanpy-menu-inset-bottom',
      `${hiddenRef.current || awayRef.current ? 0 : heightRef.current}px`,
    );

  // Phanpy slides its tab bar away while scrolling down, with a CSS rule that
  // also sets pointer-events: none (not animated, so it's reliable to read)
  const syncScrolledAway = () => {
    const nav = tabBarRef.current;
    const away = !!nav && getComputedStyle(nav).pointerEvents === 'none';
    if (away === awayRef.current) return;
    awayRef.current = away;
    syncMenuInset();
    NativeTabBar.setScrolledAway({ away });
  };

  const { i18n } = useLingui();
  const shortcutsRef = useRef(shortcuts);
  shortcutsRef.current = shortcuts;

  // Some titles are promises (e.g. a list's name), like the web bar's <AsyncText>
  const [asyncTitles, setAsyncTitles] = useState({});
  const asyncKey = shortcuts
    .filter(({ title }) => typeof title?.then === 'function')
    .map(({ path }) => path)
    .join(' ');
  useEffect(() => {
    for (const { path, title } of shortcutsRef.current) {
      if (typeof title?.then !== 'function') continue;
      Promise.resolve(title).then((text) =>
        setAsyncTitles((titles) =>
          titles[path] === text ? titles : { ...titles, [path]: text },
        ),
      );
    }
  }, [asyncKey]);

  const tabs = shortcuts.map(({ id, path, icon, altIcon, title }) => ({
    title: typeof title === 'string' ? title : asyncTitles[path] || '',
    symbol: SYMBOLS[icon] || 'circle',
    image: altIcon?.url,
    badge: id === 'notifications' && snapStates.notificationsShowNew,
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
    NativeTabBar.setTabs({
      tabs,
      selected: getSelected(),
      moreCancelTitle: i18n._(CANCEL_MESSAGE),
    });
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

  // Timelines toggle `hidden` on their header while scrolling
  useEffect(() => {
    if (!active) return;
    let frame;
    const observer = new MutationObserver(() => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(syncScrolledAway);
    });
    observer.observe(document.body, {
      subtree: true,
      attributeFilter: ['hidden'],
    });
    return () => {
      observer.disconnect();
      cancelAnimationFrame(frame);
      awayRef.current = false;
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
    NativeTabBar.setTheme({ theme: store.local.get('theme') });
    NativeTabBar.setTint({ color: getAccentHex() });
    hiddenRef.current = modalOpen || !!document.querySelector('.deck-backdrop');
    syncMenuInset();
    NativeTabBar.setHidden({ hidden: hiddenRef.current });
    // Switching pages can show/hide the web bar without a `hidden` change
    syncScrolledAway();
  }, [active, tabsKey, location.pathname, location.search, modalOpen]);

  return null;
}

export default NativeTabBarBridge;
