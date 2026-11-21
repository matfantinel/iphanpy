import { Capacitor } from '@capacitor/core';
import { useState } from 'preact/hooks';
import { Trans } from '@lingui/react/macro';

import store from '../../utils/store';

import { NATIVE_TAB_BAR_EVENT } from './native-tab-bar';

function IphanpySettings() {
  const [openLinksExternally, setOpenLinksExternally] = useState(
    store.local.getJSON('iphanpy-openLinksExternally') ?? false,
  );
  const [statusBarScroll, setStatusBarScroll] = useState(
    store.local.getJSON('iphanpy-statusBarScroll') ?? true,
  );
  const [nativeTabBar, setNativeTabBar] = useState(
    store.local.getJSON('iphanpy-nativeTabBar') ?? false,
  );

  if (!Capacitor.isNativePlatform()) return null;

  return (
    <>
      <h3>iPhanpy</h3>
      <section>
        <ul class="checkbox-list">
          <li class="block">
            <label>
              <input
                type="checkbox"
                checked={openLinksExternally}
                onChange={(e) => {
                  const { checked } = e.target;
                  store.local.setJSON('iphanpy-openLinksExternally', checked);
                  setOpenLinksExternally(checked);
                }}
              />
              <span>
                <Trans>Open external links in Default Browser</Trans>
              </span>
            </label>
            <div class="sub-section insignificant">
              <small>
                <Trans>
                  If disabled, links will be opened in the in-app browser.
                </Trans>
              </small>
            </div>
          </li>
          <li class="block">
            <label>
              <input
                type="checkbox"
                checked={statusBarScroll}
                onChange={(e) => {
                  const { checked } = e.target;
                  store.local.setJSON('iphanpy-statusBarScroll', checked);
                  setStatusBarScroll(checked);
                }}
              />
              <span>
                <Trans>Tap status bar to scroll to top</Trans>
              </span>
            </label>
          </li>
          <li class="block">
            <label>
              <input
                type="checkbox"
                checked={nativeTabBar}
                onChange={(e) => {
                  const { checked } = e.target;
                  store.local.setJSON('iphanpy-nativeTabBar', checked);
                  setNativeTabBar(checked);
                  window.dispatchEvent(new Event(NATIVE_TAB_BAR_EVENT));
                }}
              />
              <span>
                <Trans>Use native tab bar</Trans>
              </span>
            </label>
            <div class="sub-section insignificant">
              <small>
                <Trans>
                  Experimental. Applies when shortcuts are shown as a tab bar.
                </Trans>
              </small>
            </div>
          </li>
        </ul>
      </section>
    </>
  );
}

export default IphanpySettings;
