#import "GoogleMlKitImageLabelingPlugin.h"

#define channelName @"google_mlkit_image_labeler"
#define startImageLabelDetector @"vision#startImageLabelDetector"
#define closeImageLabelDetector @"vision#closeImageLabelDetector"
#define manageFirebaseModels @"vision#manageFirebaseModels"

@implementation GoogleMlKitImageLabelingPlugin {
    NSMutableDictionary *instances;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
                                     methodChannelWithName:channelName
                                     binaryMessenger:[registrar messenger]];
    GoogleMlKitImageLabelingPlugin* instance = [[GoogleMlKitImageLabelingPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (id)init {
    self = [super init];
    if (self)
        instances = [NSMutableDictionary dictionary];
    return  self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:startImageLabelDetector]) {
        result([FlutterError errorWithCode:@"UNSUPPORTED_IOS_MLKIT"
                                   message:@"Image labeling is unavailable in this iOS build."
                                   details:@"The bundled ML Kit CocoaPods do not currently support the required Apple Silicon simulator architecture."]);
    } else if ([call.method isEqualToString:closeImageLabelDetector]) {
        NSString *uid = call.arguments[@"id"];
        [instances removeObjectForKey:uid];
        result(NULL);
    } else if ([call.method isEqualToString:manageFirebaseModels]) {
        result([FlutterError errorWithCode:@"UNSUPPORTED_IOS_MLKIT"
                                   message:@"Firebase-hosted ML Kit models are unavailable in this iOS build."
                                   details:@"This app uses a local fallback on iOS until the upstream ML Kit CocoaPods support Apple Silicon simulator builds."]);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

@end
