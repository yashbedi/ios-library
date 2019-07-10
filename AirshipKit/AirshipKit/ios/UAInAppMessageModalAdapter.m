/* Copyright Airship and Contributors */

#import "UAGlobal.h"
#import "UAInAppMessageModalAdapter.h"
#import "UAInAppMessageModalDisplayContent+Internal.h"
#import "UAInAppMessageModalViewController+Internal.h"
#import "UAInAppMessageHTMLViewController+Internal.h"
#import "UAInAppMessageMediaView+Internal.h"
#import "UAInAppMessageUtils+Internal.h"
#import "UAUtils+Internal.h"
#import "UAInAppMessageResizableViewController+Internal.h"


NSString *const UAModalStyleFileName = @"UAInAppMessageModalStyle";

@interface UAInAppMessageModalAdapter ()
@property (nonatomic, strong) UAInAppMessage *message;
@property (nonatomic, strong) UAInAppMessageModalViewController *modalController;
@property (nonatomic, strong) UAInAppMessageResizableViewController *resizableContainerViewController;
@property (nonatomic, strong, nullable) UIWindowScene *scene API_AVAILABLE(ios(13.0));

@end

@implementation UAInAppMessageModalAdapter

+ (instancetype)adapterForMessage:(UAInAppMessage *)message {
    return [[UAInAppMessageModalAdapter alloc] initWithMessage:message];
}

-(instancetype)initWithMessage:(UAInAppMessage *)message {
    self = [super init];

    if (self) {
        self.message = message;
        self.style = [UAInAppMessageModalStyle styleWithContentsOfFile:UAModalStyleFileName];
    }

    return self;
}

- (void)prepareWithAssets:(nonnull UAInAppMessageAssets *)assets completionHandler:(nonnull void (^)(UAInAppMessagePrepareResult))completionHandler {
    UAInAppMessageModalDisplayContent *displayContent = (UAInAppMessageModalDisplayContent *)self.message.displayContent;
    [UAInAppMessageUtils prepareMediaView:displayContent.media assets:assets completionHandler:^(UAInAppMessagePrepareResult result, UAInAppMessageMediaView *mediaView) {
        if (result == UAInAppMessagePrepareResultSuccess) {
            mediaView.hideWindowWhenVideoIsFullScreen = YES;
            self.modalController = [UAInAppMessageModalViewController modalControllerWithModalMessageID:self.message.identifier
                                                                                         displayContent:displayContent
                                                                                              mediaView:mediaView
                                                                                                  style:self.style];
        }
        completionHandler(result);
    }];
}

- (BOOL)isReadyToDisplay {
    UAInAppMessageModalDisplayContent* modalContent = (UAInAppMessageModalDisplayContent *)self.message.displayContent;
    return [UAInAppMessageUtils isReadyToDisplayWithMedia:modalContent.media];
}

- (void)display:(void (^)(UAInAppMessageResolution *))completionHandler {

    self.resizableContainerViewController = [UAInAppMessageResizableViewController resizableViewControllerWithChild:self.modalController];

    self.resizableContainerViewController.backgroundColor = self.modalController.displayContent.backgroundColor;
    self.resizableContainerViewController.allowFullScreenDisplay = self.modalController.displayContent.allowFullScreenDisplay;
    self.resizableContainerViewController.additionalPadding = self.modalController.style.additionalPadding;
    self.resizableContainerViewController.borderRadius = self.modalController.displayContent.borderRadiusPoints;
    self.resizableContainerViewController.maxWidth = self.modalController.style.maxWidth;
    self.resizableContainerViewController.maxHeight = self.modalController.style.maxHeight;

    // Set weak link to parent
    self.modalController.resizableParent = self.resizableContainerViewController;

    // Show resizable view controller with child
    if (@available(iOS 13.0, *)) {
        [self.resizableContainerViewController showWithCompletionHandler:completionHandler scene:self.scene];
    } else {
        [self.resizableContainerViewController showWithCompletionHandler:completionHandler];
    }
}

- (void)display:(void (^)(UAInAppMessageResolution *))completionHandler
          scene:(nullable UIWindowScene *)scene API_AVAILABLE(ios(13.0)){
    self.scene = scene;
    [self display:completionHandler];
}

@end
