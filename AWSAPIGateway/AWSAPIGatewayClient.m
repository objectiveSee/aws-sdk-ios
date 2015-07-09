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

#import "AWSAPIGatewayClient.h"
#import <AWSCore/AWSCore.h>

NSString *const AWSAPIGatewayAPIKeyHeader = @"x-api-key";

@interface AWSAPIGatewayClient()

// Networking
@property (nonatomic, strong) NSURLSession *session;

// For responses
@property (nonatomic, strong) NSDictionary *HTTPHeaderFields;
@property (nonatomic, assign) NSInteger HTTPStatusCode;

@end

@implementation AWSAPIGatewayClient

- (instancetype)init {
    if (self = [super init]) {
        static NSURLSession *session = nil;

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
            session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
        });

        _session = session;
    }
    return self;
}

- (AWSTask *)invokeHTTPRequest:(NSString *)HTTPMethod
                     URLString:(NSString *)URLString
                pathParameters:(NSDictionary *)pathParameters
               queryParameters:(NSDictionary *)queryParameters
              headerParameters:(NSDictionary *)headerParameters
                          body:(id)body
                 responseClass:(Class)responseClass {
    NSURL *URL = [self requestURL:URLString query:queryParameters URLPathComponentsDictionary:pathParameters];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    request.HTTPMethod = HTTPMethod;
    request.allHTTPHeaderFields = headerParameters;
    if (self.APIKey) {
        [request addValue:self.APIKey forHTTPHeaderField:AWSAPIGatewayAPIKeyHeader];
    }

    NSError *error = nil;
    if (body != nil) {
        NSDictionary *bodyParameters = [[AWSMTLJSONAdapter JSONDictionaryFromModel:body] aws_removeNullValues];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:bodyParameters
                                                           options:0
                                                             error:&error];
        if (!request.HTTPBody) {
            AWSLogError(@"Failed to serialize a request body. %@", error);
        }
    }

    // Refreshes credentials if necessary
    AWSTask *task = [AWSTask taskWithResult:nil];
    task = [task continueWithSuccessBlock:^id(AWSTask *task) {
        id signer = [self.configuration.requestInterceptors lastObject];
        if (signer) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
            if ([signer respondsToSelector:@selector(credentialsProvider)]) {
                id credentialsProvider = [signer performSelector:@selector(credentialsProvider)];

                if ([credentialsProvider respondsToSelector:@selector(refresh)]) {
                    NSString *accessKey = nil;
                    if ([credentialsProvider respondsToSelector:@selector(accessKey)]) {
                        accessKey = [credentialsProvider performSelector:@selector(accessKey)];
                    }

                    NSString *secretKey = nil;
                    if ([credentialsProvider respondsToSelector:@selector(secretKey)]) {
                        secretKey = [credentialsProvider performSelector:@selector(secretKey)];
                    }

                    NSDate *expiration = nil;
                    if  ([credentialsProvider respondsToSelector:@selector(expiration)]) {
                        expiration = [credentialsProvider performSelector:@selector(expiration)];
                    }

                    /**
                     Preemptively refresh credentials if any of the following is true:
                     1. accessKey or secretKey is nil.
                     2. the credentials expires within 10 minutes.
                     */
                    if ((!accessKey || !secretKey)
                        || [expiration compare:[NSDate dateWithTimeIntervalSinceNow:10 * 60]] == NSOrderedAscending) {
                        return [credentialsProvider performSelector:@selector(refresh)];
                    }
                }
            }
#pragma clang diagnostic pop
        }
        return nil;
    }];

    // Signs the request
    for (id<AWSNetworkingRequestInterceptor> interceptor in self.configuration.requestInterceptors) {
        task = [task continueWithSuccessBlock:^id(AWSTask *task) {
            return [interceptor interceptRequest:request];
        }];
    }

    return [task continueWithSuccessBlock:^id(AWSTask *task) {
        AWSTaskCompletionSource *completionSource = [AWSTaskCompletionSource new];

        NSURLSessionDataTask *sessionTask = [self.session dataTaskWithRequest:request
                                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                                if (error) {
                                                                    [completionSource setError:error];
                                                                    return;
                                                                }
                                                                if (response) {
                                                                    NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)response;
                                                                    self.HTTPHeaderFields = HTTPResponse.allHeaderFields;
                                                                    self.HTTPStatusCode = HTTPResponse.statusCode;
                                                                }
                                                                if (data && [data length] > 0) {
                                                                    id response = [NSJSONSerialization JSONObjectWithData:data
                                                                                                                  options:NSJSONReadingAllowFragments
                                                                                                                    error:&error];
                                                                    if (!response) {
                                                                        NSString *bodyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                                                        if ([bodyString length] > 0) {
                                                                            AWSLogError(@"The body is not in JSON format. Body: %@\nError: %@", bodyString, error);
                                                                            [completionSource setError:error];
                                                                            return;
                                                                        }
                                                                    }
                                                                    // Serializes the response object
                                                                    if (responseClass
                                                                        && responseClass != [NSDictionary class]) {
                                                                        if ([response isKindOfClass:[NSDictionary class]]) {
                                                                            NSError *responseSerializationError = nil;
                                                                            response = [AWSMTLJSONAdapter modelOfClass:responseClass
                                                                                                    fromJSONDictionary:response
                                                                                                                 error:&responseSerializationError];
                                                                            if (!response) {
                                                                                AWSLogError(@"Failed to serialize the body JSON. %@", responseSerializationError);
                                                                            }
                                                                        }
                                                                        if ([response isKindOfClass:[NSArray class]]) {
                                                                            NSError *responseSerializationError = nil;
                                                                            NSMutableArray *models = [NSMutableArray new];
                                                                            for (id object in response) {
                                                                                id model = [AWSMTLJSONAdapter modelOfClass:responseClass
                                                                                                        fromJSONDictionary:object
                                                                                                                     error:&responseSerializationError];
                                                                                [models addObject:model];
                                                                                if (!response) {
                                                                                    AWSLogError(@"Failed to serialize the body JSON. %@", responseSerializationError);
                                                                                }
                                                                            }
                                                                            response = models;
                                                                        }
                                                                    }
                                                                    [completionSource setResult:response];
                                                                } else {
                                                                    [completionSource setResult:nil];
                                                                }
                                                            }];
        [sessionTask resume];
        
        return completionSource.task;
    }];
}

- (NSURL *)requestURL:(NSString *)URLString query:(NSDictionary *)query URLPathComponentsDictionary:(NSDictionary *)URLPathComponentsDictionary {
    NSMutableString *mutableURLString = [NSMutableString stringWithString:URLString];

    // Constructs the URL path components
    NSCharacterSet *delimiters = [NSCharacterSet characterSetWithCharactersInString:@"{}"];
    NSArray *URLPathComponents = [URLString componentsSeparatedByCharactersInSet:delimiters];
    if ([URLPathComponents count] >= 2) {
        for (NSUInteger i = 1; i < [URLPathComponents count] - 1; i++) {
            [mutableURLString replaceOccurrencesOfString:[NSString stringWithFormat:@"{%@}", URLPathComponents[i]]
                                              withString:[self encodeQueryStringValue:[URLPathComponentsDictionary valueForKey:URLPathComponents[i]]]
                                          options:NSLiteralSearch
                                            range:NSMakeRange(0, [mutableURLString length])];
        }
    }

    // Adds query string
    NSMutableString *queryString = [NSMutableString new];
    [self processParameters:query queryString:queryString];
    if ([queryString length] > 0) {
        [mutableURLString appendFormat:@"?%@", queryString];
    }

    return [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", self.configuration.baseURL, mutableURLString]];
}

// TODO: merge it with - (void)processParameters:(NSDictionary *)parameters queryString:(NSMutableString *)queryString in AWSURLRequestSerialization.m
- (void)processParameters:(NSDictionary *)parameters queryString:(NSMutableString *)queryString {
    for (NSString *key in parameters) {
        id obj = parameters[key];

        if ([obj isKindOfClass:[NSDictionary class]]) {
            [self processParameters:obj queryString:queryString];
        } else {
            if ([queryString length] > 0) {
                [queryString appendString:@"&"];
            }

            [queryString appendString:[self generateQueryStringWithKey:key value:obj]];
        }
    }
}

- (NSString *)generateQueryStringWithKey:(NSString *)key value:(id)value {
    NSMutableString *queryString = [NSMutableString new];
    [queryString appendString:[key aws_stringWithURLEncoding]];
    [queryString appendString:@"="];
    [queryString appendString:[self encodeQueryStringValue:value]];

    return queryString;
}

- (NSString *)encodeQueryStringValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [value aws_stringWithURLEncoding];
    }

    if ([value isKindOfClass:[NSNumber class]]) {
        return [[value stringValue] aws_stringWithURLEncoding];
    }

    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableString *mutableString = [NSMutableString new];
        for (id obj in value) {
            if ([mutableString length] > 0) {
                [mutableString appendString:@","];
            }
            [mutableString appendString:[self encodeQueryStringValue:obj]];
        }
        return mutableString;
    }

    AWSLogError(@"value[%@] is invalid.", value);
    return [[value description] aws_stringWithURLEncoding];
}

@end
