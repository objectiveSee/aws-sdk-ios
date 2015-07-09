/*
 Copyright 2010-2015 Amazon.com, Inc. or its affiliates. All Rights Reserved.

 Licensed under the Apache License, Version 2.0 (the "License").
 You may not use this file except in compliance with the License.
 A copy of the License is located at

 http://aws.amazon.com/apache2.0

 or in the "license" file accompanying this file. This file is distributed
 on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 express or implied. See the License for the specific language governing
 permissions and limitations under the License.
 */

#if !AWS_TEST_BJS_INSTEAD

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "AWSCore.h"
#import "AWSTestUtility.h"
#import "AWSMobileAnalyticsERS.h"

@interface AWSMobileAnalyticsERSTests : XCTestCase

@end

@implementation AWSMobileAnalyticsERSTests

- (void)setUp
{
    [super setUp];
    [AWSTestUtility setupCognitoCredentialsProvider];
}

- (void)tearDown
{
    [super tearDown];
}

- (void)testPutEvents {
    AWSMobileAnalyticsERS *ers = [AWSMobileAnalyticsERS defaultMobileAnalyticsERS];
    
    AWSMobileAnalyticsERSPutEventsInput *putEventInput = [AWSMobileAnalyticsERSPutEventsInput new];

    
    AWSMobileAnalyticsERSEvent *eventOne = [AWSMobileAnalyticsERSEvent new];
    
    eventOne.attributes = @{};
    eventOne.version = @"v2.0";
    eventOne.eventType = @"_session.start";
    eventOne.timestamp = [[NSDate date] aws_stringValue:AWSDateISO8601DateFormat3];
    
    AWSMobileAnalyticsERSSession *serviceSession = [AWSMobileAnalyticsERSSession new];
    serviceSession.identifier = @"SMZSP1G8-21c9ac01-20140604-171714026";
    serviceSession.startTimestamp = [[NSDate date] aws_stringValue:AWSDateISO8601DateFormat3];
    
    eventOne.session = serviceSession;
    
    putEventInput.events = @[eventOne];
    
    NSDictionary *clientContext = @{@"client": @{@"app_package_name": @"MT3T3XMSMZSP1G8",
                                                 @"app_version_name":@"v1.2",
                                                 @"app_version_code":@"3",
                                                 @"app_title":[NSNull null],
                                                 @"client_id":@"0a877e9d-c7c0-4269-b138-cb3f21c9ac01"
                                                 },
                                    @"env" : @{@"model": @"iPhone Simulator",
                                               @"make":@"Apple",
                                               @"platform":@"IOS",
                                               @"platform_version":@"4.3.1",
                                               @"locale":@"en-US"},
                                    @"custom" : @{},
                                    };
    NSString *clientContextJsonString = [[NSString alloc] initWithData: [NSJSONSerialization dataWithJSONObject:clientContext options:0 error:nil] encoding:NSUTF8StringEncoding];
    
    putEventInput.clientContext = clientContextJsonString;
    
    __block int64_t totalUploadedBytes = 0;
    __block int64_t totalExpectedUploadBytes = 0;
    putEventInput.uploadProgress = ^(int64_t bytesSent, int64_t totalBytesSent, int64_t totalBytesExpectedToSend) {
        
        NSLog(@"bytesSent: %lld, totalBytesSent: %lld, totalBytesExpectedToSend: %lld",bytesSent,totalBytesSent,totalBytesExpectedToSend);
        totalUploadedBytes = totalBytesSent;
        totalExpectedUploadBytes = totalBytesExpectedToSend;
    };
    
    [[[ers putEvents:putEventInput] continueWithBlock:^id(AWSTask *task) {
        XCTAssertNil(task.error, @"The request failed. error: [%@]", task.error);
        XCTAssertTrue([task.result isKindOfClass:[NSDictionary class]], @"The response object is not a class of [%@]", NSStringFromClass([NSDictionary class]));
        XCTAssertEqualObjects(task.result[@"responseStatusCode"], @202);
        XCTAssertNotNil(task.result[@"responseDataSize"]);
        XCTAssertNotNil(task.result[@"responseHeaders"]);
        
        return nil;
        
    }] waitUntilFinished ];
    
    XCTAssertTrue(totalUploadedBytes > 0);
    XCTAssertTrue(totalExpectedUploadBytes > 0);
}

- (void)testPutEventsCancelled {
    AWSMobileAnalyticsERS *ers = [AWSMobileAnalyticsERS defaultMobileAnalyticsERS];
    
    AWSMobileAnalyticsERSPutEventsInput *putEventInput = [AWSMobileAnalyticsERSPutEventsInput new];
    
    
    AWSMobileAnalyticsERSEvent *eventOne = [AWSMobileAnalyticsERSEvent new];
    
    eventOne.attributes = @{};
    eventOne.version = @"v2.0";
    eventOne.eventType = @"_session.start";
    eventOne.timestamp = [[NSDate date] aws_stringValue:AWSDateISO8601DateFormat3];
    
    AWSMobileAnalyticsERSSession *serviceSession = [AWSMobileAnalyticsERSSession new];
    serviceSession.identifier = @"SMZSP1G8-21c9ac01-20140604-171714026";
    serviceSession.startTimestamp = [[NSDate date] aws_stringValue:AWSDateISO8601DateFormat3];
    
    eventOne.session = serviceSession;
    
    putEventInput.events = @[eventOne];
    
    NSDictionary *clientContext = @{@"client": @{@"app_package_name": @"MT3T3XMSMZSP1G8",
                                                 @"app_version_name":@"v1.2",
                                                 @"app_version_code":@"3",
                                                 @"app_title":[NSNull null],
                                                 @"client_id":@"0a877e9d-c7c0-4269-b138-cb3f21c9ac01"
                                                 },
                                    @"env" : @{@"model": @"iPhone Simulator",
                                               @"make":@"Apple",
                                               @"platform":@"IOS",
                                               @"platform_version":@"4.3.1",
                                               @"locale":@"en-US"},
                                    @"custom" : @{},
                                    };
    NSString *clientContextJsonString = [[NSString alloc] initWithData: [NSJSONSerialization dataWithJSONObject:clientContext options:0 error:nil] encoding:NSUTF8StringEncoding];
    
    putEventInput.clientContext = clientContextJsonString;

    //cancel it before task starts.
    [putEventInput cancel];
    AWSTask *putEventtask = [[ers putEvents:putEventInput] continueWithBlock:^id(AWSTask *task) {
        
        XCTAssertNotNil(task.error,@"Expect got 'Cancelled' Error, but got nil");
        XCTAssertEqualObjects(AWSNetworkingErrorDomain, task.error.domain);
        XCTAssertEqual(AWSNetworkingErrorCancelled, task.error.code);
        
        return nil;
        
    }];
    
    [putEventtask waitUntilFinished];
    XCTAssertTrue(putEventInput.isCancelled);
}
@end

#endif