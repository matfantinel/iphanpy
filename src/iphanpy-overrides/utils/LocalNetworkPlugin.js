import { registerPlugin } from '@capacitor/core';

const LocalNetwork = registerPlugin('LocalNetworkPlugin', {
  web: () => ({
    requestPermission: async () => {
      console.log('Local network permission not needed on web');
    }
  })
});

export default LocalNetwork;