#import <Capacitor/Capacitor.h>

CAP_PLUGIN(LocalNetworkPlugin, "LocalNetworkPlugin",
    CAP_PLUGIN_METHOD(requestPermission, CAPPluginReturnPromise);
)
