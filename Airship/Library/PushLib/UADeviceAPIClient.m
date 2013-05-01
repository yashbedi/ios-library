
#import "UADeviceAPIClient.h"
#import "UAGlobal.h"
#import "UAirship.h"
#import "UAUtils.h"
#import "UA_SBJsonWriter.h"
#import "UAHTTPConnectionOperation.h"

#define kUAPushRetryTimeInitialDelay 60
#define kUAPushRetryTimeMultiplier 2
#define kUAPushRetryTimeMaxDelay 300

@interface UADeviceAPIClient()

@property(nonatomic, retain) UAHTTPRequestEngine *requestEngine;
@property(nonatomic, retain) UADeviceRegistrationData *lastSuccessfulRegistration;
@property(nonatomic, retain) UADeviceRegistrationData *pendingRegistration;

@end

@implementation UADeviceAPIClient

- (id)init {
    if (self = [super init]) {
        self.shouldRetryOnConnectionError = YES;
        self.requestEngine = [[[UAHTTPRequestEngine alloc] init] autorelease];
        self.requestEngine.initialDelayIntervalInSeconds = kUAPushRetryTimeInitialDelay;
        self.requestEngine.maxDelayIntervalInSeconds = kUAPushRetryTimeMaxDelay;
        self.requestEngine.backoffFactor = kUAPushRetryTimeMultiplier;
    }
    return self;
}

- (UAHTTPRequest *)requestToRegisterDeviceTokenWithData:(UADeviceRegistrationData *)registrationData {
    NSString *urlString = [NSString stringWithFormat:@"%@%@%@/",
                           [UAirship shared].server, @"/api/device_tokens/",
                           registrationData.deviceToken];
    NSURL *url = [NSURL URLWithString:urlString];
    UAHTTPRequest *request = [UAUtils UAHTTPRequestWithURL:url method:@"PUT"];

    if (registrationData.payload != nil) {
        [request addRequestHeader: @"Content-Type" value: @"application/json"];
        UA_SBJsonWriter *writer = [[[UA_SBJsonWriter alloc] init] autorelease];
        [request appendBodyData:[[writer stringWithObject:registrationData.payload] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    return request;
}

- (UAHTTPRequest *)requestToDeleteDeviceTokenWithData:(UADeviceRegistrationData *)registrationData {
    NSString *urlString = [NSString stringWithFormat:@"%@/api/device_tokens/%@/",
                           [UAirship shared].server,
                           registrationData.deviceToken];
    NSURL *url = [NSURL URLWithString:urlString];
    UAHTTPRequest *request = [UAUtils UAHTTPRequestWithURL:url method:@"DELETE"];

    return request;
}

//we want to avoid sending duplicate payloads, when possible
- (BOOL)shouldSendRegistrationWithData:(UADeviceRegistrationData *)data {
    //if there's already one going out
    if (self.pendingRegistration) {
        //return NO if it's equal to the current data
        return ![self.pendingRegistration isEqual:data];
    } else {
        //otherwise if there was a previous successful registration/unregistration
        if (self.lastSuccessfulRegistration) {
            //return NO if it's equal to the current data
            return ![self.lastSuccessfulRegistration isEqual:data];
        } else {
            return YES;
        }
    }
}

- (void)runRequest:(UAHTTPRequest *)request
          withData:(UADeviceRegistrationData *)registrationData
      succeedWhere:(UAHTTPRequestEngineWhereBlock)succeedWhereBlock
        retryWhere:(UAHTTPRequestEngineWhereBlock)retryWhereBlock
         onSuccess:(UADeviceAPIClientSuccessBlock)successBlock
         onFailure:(UADeviceAPIClientFailureBlock)failureBlock
        forcefully:(BOOL)forcefully {

    //if the forcefully flag is set, we don't care about what we haved cached, otherwise make sure it's not a duplicate
    if (forcefully || [self shouldSendRegistrationWithData:registrationData]) {

        [self.requestEngine cancelPendingRequests];

        //synchronize here since we're messing with the registration cache
        //the success/failure blocks below will be triggered on the main thread
        @synchronized(self) {
            self.pendingRegistration = registrationData;
        }

        [self.requestEngine
         runRequest:request
         succeedWhere:succeedWhereBlock
         retryWhere:retryWhereBlock
         onSuccess:^(UAHTTPRequest *request) {
             //clear the pending cache,  update last successful cache
             self.pendingRegistration = nil;
             self.lastSuccessfulRegistration = registrationData;
             successBlock();
         }
         onFailure:^(UAHTTPRequest *request) {
             //clear the pending cache
             self.pendingRegistration = nil;
             failureBlock(request);
         }];
    } else {
        UA_LDEBUG(@"Ignoring duplicate request");
    }
}

- (void)registerWithData:(UADeviceRegistrationData *)registrationData
               onSuccess:(UADeviceAPIClientSuccessBlock)successBlock
               onFailure:(UADeviceAPIClientFailureBlock)failureBlock
              forcefully:(BOOL)forcefully {

    UAHTTPRequest *putRequest = [self requestToRegisterDeviceTokenWithData:registrationData];

    UA_LDEBUG(@"Running device registration");

    [self
     runRequest:putRequest withData:registrationData
     succeedWhere:^(UAHTTPRequest *request) {
        NSInteger status = request.response.statusCode;
        return (BOOL)(status == 200 || status == 201);
     }
     retryWhere:^(UAHTTPRequest *request) {
         NSInteger status = request.response.statusCode;
         return (BOOL)(status >= 500 && status <= 599 && self.shouldRetryOnConnectionError);
     }
     onSuccess:successBlock
     onFailure:failureBlock
     forcefully:forcefully];
}

- (void)registerWithData:(UADeviceRegistrationData *)registrationData
               onSuccess:(UADeviceAPIClientSuccessBlock)successBlock
               onFailure:(UADeviceAPIClientFailureBlock)failureBlock {
    [self registerWithData:registrationData onSuccess:successBlock onFailure:failureBlock forcefully:NO];
}

- (void)unregisterWithData:(UADeviceRegistrationData *)registrationData
                 onSuccess:(UADeviceAPIClientSuccessBlock)successBlock
                 onFailure:(UADeviceAPIClientFailureBlock)failureBlock
                forcefully:(BOOL)forcefully {

    UAHTTPRequest *deleteRequest = [self requestToDeleteDeviceTokenWithData:registrationData];

    UA_LDEBUG(@"Running device unregistration");

    [self
     runRequest:deleteRequest withData:registrationData
     succeedWhere:^(UAHTTPRequest *request) {
         NSInteger status = request.response.statusCode;
         return (BOOL)(status == 204);
     }
     retryWhere:^(UAHTTPRequest *request) {
         NSInteger status = request.response.statusCode;
         return (BOOL)(status >= 500 && status <= 599 && self.shouldRetryOnConnectionError);
     }
     onSuccess:successBlock
     onFailure:failureBlock
     forcefully:forcefully];
};

- (void)unregisterWithData:(UADeviceRegistrationData *)registrationData
               onSuccess:(UADeviceAPIClientSuccessBlock)successBlock
               onFailure:(UADeviceAPIClientFailureBlock)failureBlock {
    [self unregisterWithData:registrationData onSuccess:successBlock onFailure:failureBlock forcefully:NO];
}

- (void)dealloc {
    self.requestEngine = nil;
    self.lastSuccessfulRegistration = nil;
    self.pendingRegistration = nil;
    [super dealloc];
}

@end
