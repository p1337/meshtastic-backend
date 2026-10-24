#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(ClickBridgeModule, RCTEventEmitter)
RCT_EXTERN_METHOD(arm:(BOOL)enabled resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(report:(NSString *)identifier result:(NSString *)result)
RCT_EXTERN_METHOD(presentSetup)
@end
