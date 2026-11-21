import { Capacitor } from '@capacitor/core';
import { useState } from 'preact/hooks';
import { Trans } from '@lingui/react/macro';

import store from '../../utils/store';

function IphanpySettings() {
  const [openLinksExternally, setOpenLinksExternally] = useState(
    store.local.get('iphanpy-openLinksExternally') ?? false,
  );
  const [statusBarScroll, setStatusBarScroll] = useState(
    store.local.get('iphanpy-statusBarScroll') ?? true,
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
                  store.local.set('iphanpy-openLinksExternally', checked);
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
                  store.local.set('iphanpy-statusBarScroll', checked);
                  setStatusBarScroll(checked);
                }}
              />
              <span>
                <Trans>Tap status bar to scroll to top</Trans>
              </span>
            </label>
          </li>
        </ul>
      </section>
    </>
  );
}

export default IphanpySettings;
