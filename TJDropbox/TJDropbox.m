//
//  TJDropbox.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "TJDropbox.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const TJDropboxErrorDomain = @"TJDropboxErrorDomain";
NSString *const TJDropboxErrorUserInfoKeyResponse = @"response";
NSString *const TJDropboxErrorUserInfoKeyDropboxError = @"dropboxError";
NSString *const TJDropboxErrorUserInfoKeyErrorString = @"errorString";

@interface TJDropboxCredential ()

@property (nonatomic, copy, readwrite) NSString *accessToken;

@end

@implementation TJDropboxCredential

- (instancetype)initWithAccessToken:(NSString *const)accessToken
{
    if (self = [super init]) {
        self.accessToken = accessToken;
    }
    return self;
}

@end

#if defined(__has_attribute) && __has_attribute(objc_direct_members)
__attribute__((objc_direct_members))
#endif
@interface TJDropboxURLSessionTaskDelegate : NSObject <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>

/**
 * Outside classes (such as TJDropbox) should not access these properties directly!
 * They should be accessed via -setProgressBlock:completionBlock:for*Task: ONLY to ensure safety is maintained.
 */

@property (nonatomic) NSMutableDictionary<NSURLSessionTask *, void (^)(CGFloat)> *progressBlocksForTasks;
@property (nonatomic) NSMutableDictionary<NSURLSessionTask *, NSMutableData *> *accumulatedDataForDataTasks;
@property (nonatomic) NSMutableDictionary *completionBlocksForTasks;

// This serial queue must be used for the following:
//   - as the NSURLSession delegateQueue
//   - when accessing the task delegate's block and accumulatedData dictionaries
// This ensures that these dictionaries are only accessed by one thread at once.
@property (nonatomic) NSOperationQueue *serialOperationQueue;

@end

#if defined(__has_attribute) && __has_attribute(objc_direct_members)
__attribute__((objc_direct_members))
#endif
@implementation TJDropboxURLSessionTaskDelegate

- (instancetype)init
{
    if (self = [super init]) {
        self.accumulatedDataForDataTasks = [NSMutableDictionary new];
        self.progressBlocksForTasks = [NSMutableDictionary new];
        self.completionBlocksForTasks = [NSMutableDictionary new];
        
        NSOperationQueue *serialOperationQueue = [NSOperationQueue new];
        // make serial
        serialOperationQueue.maxConcurrentOperationCount = 1;
        serialOperationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        self.serialOperationQueue = serialOperationQueue;
    }
    return self;
}

- (void)setProgressBlock:(nullable void (^const)(CGFloat progress))progressBlock
         completionBlock:(nullable void (^const)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error))completionBlock
             forDataTask:(NSURLSessionDataTask *const)task
{
    [self _setProgressBlock:progressBlock
            completionBlock:completionBlock
                    forTask:task
              expectedClass:[NSURLSessionDataTask class]];
}

- (void)setProgressBlock:(nullable void (^const)(CGFloat progress))progressBlock
         completionBlock:(nullable void (^const)(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error))completionBlock
         forDownloadTask:(NSURLSessionDownloadTask *const)task
{
        [self _setProgressBlock:progressBlock
                completionBlock:completionBlock
                        forTask:task
                  expectedClass:[NSURLSessionDownloadTask class]];
}

- (void)_setProgressBlock:(nullable void (^const)(CGFloat progress))progressBlock
          completionBlock:(nullable const id)completionBlock
                  forTask:(NSURLSessionTask *const)task
            expectedClass:(Class)expectedClass
{
    if ([task isKindOfClass:expectedClass]) {
        [self.serialOperationQueue addOperationWithBlock:^{
            if (progressBlock) {
                [self.progressBlocksForTasks setObject:progressBlock forKey:task];
            }
            if (completionBlock) {
                [self.completionBlocksForTasks setObject:completionBlock forKey:task];
            }
        }];
    } else {
        NSAssert(NO, @"Adding wrong completion setup for task with type %@, was expecting %@.", NSStringFromClass([task class]), NSStringFromClass(expectedClass));
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    void (^progressBlock)(CGFloat progress) = self.progressBlocksForTasks[task];
    
    if (progressBlock && totalBytesExpectedToSend > 0) {
        progressBlock((CGFloat)totalBytesSent / totalBytesExpectedToSend);
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    void (^progressBlock)(CGFloat progress) = self.progressBlocksForTasks[task];
    
    if (progressBlock && totalBytesExpectedToWrite > 0) {
        progressBlock((CGFloat)totalBytesWritten / totalBytesExpectedToWrite);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data
{
    NSMutableData *accumulatedData = self.accumulatedDataForDataTasks[task];
    if (accumulatedData) {
        [accumulatedData appendData:data];
    } else {
        self.accumulatedDataForDataTasks[task] = [data mutableCopy];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    // Catches the case where the task failed.
    [self tryCompleteTask:task location:nil data:self.accumulatedDataForDataTasks[task]];
    
    [self.progressBlocksForTasks removeObjectForKey:task];
    [self.accumulatedDataForDataTasks removeObjectForKey:task];
    [self.completionBlocksForTasks removeObjectForKey:task];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location
{
    // Catches the case where the file was downloaded successfully.
    [self tryCompleteTask:task location:location data:nil];
}

- (void)tryCompleteTask:(NSURLSessionTask *const)task location:(NSURL *const)location data:(NSData *const)data
{
    if ([task isKindOfClass:[NSURLSessionDownloadTask class]]) {
        void (^downloadCompletionBlock)(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) = self.completionBlocksForTasks[task];
        if (downloadCompletionBlock) {
            downloadCompletionBlock(location, task.response, task.error);
        }
    } else if ([task isKindOfClass:[NSURLSessionDataTask class]]) {
        void (^dataCompletionBlock)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) = self.completionBlocksForTasks[task];
        if (dataCompletionBlock) {
            dataCompletionBlock(self.accumulatedDataForDataTasks[task], task.response, task.error);
        }
    } else {
        NSAssert(NO, @"This shouldn't be reached");
    }
    [self.completionBlocksForTasks removeObjectForKey:task];
}

@end

#if defined(__has_attribute) && __has_attribute(objc_direct_members)
__attribute__((objc_direct_members))
#endif
@implementation TJDropbox

#pragma mark - Authentication

// Copied from https://bit.ly/2NeKGi2
static NSString *_codeChallengeFromCodeVerifier(NSString *const codeVerifier)
{
  // Creates code challenge according to [RFC7636 4.2] (https://tools.ietf.org/html/rfc7636#section-4.2)
  // 1. Covert code verifier to ascii encoded string.
  // 2. Compute the SHA256 hash of the ascii string.
  // 3. Base64 encode the resulting hash.
  // 4. Make the Base64 string URL safe by replacing a few characters. (https://tools.ietf.org/html/rfc4648#section-5)
  const char *asciiString = [codeVerifier cStringUsingEncoding:NSASCIIStringEncoding];
  NSData *data = [NSData dataWithBytes:asciiString length:strlen(asciiString)];
  unsigned char digest[CC_SHA256_DIGEST_LENGTH] = {0};
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSData *sha256Data = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
  NSString *base64String = [sha256Data base64EncodedStringWithOptions:kNilOptions];
  base64String = [base64String stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  base64String = [base64String stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  base64String = [base64String stringByReplacingOccurrencesOfString:@"=" withString:@""];
  return base64String;
}

+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier
                                          redirectURL:(nullable NSURL *)redirectURL
                                         codeVerifier:(nullable NSString *const)codeVerifier
{
    // https://www.dropbox.com/developers/documentation/http/documentation#auth
    
    if (!redirectURL) {
        redirectURL = [self defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier];
    }
    NSString *const codeChallenge = codeVerifier ? _codeChallengeFromCodeVerifier(codeVerifier) : nil;
    
    NSURLComponents *const components = [NSURLComponents componentsWithURL:[NSURL URLWithString:@"https://www.dropbox.com/oauth2/authorize"] resolvingAgainstBaseURL:NO];
    components.queryItems = [NSArray arrayWithObjects:
                             [NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
                             [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURL.absoluteString],
                             [NSURLQueryItem queryItemWithName:@"response_type" value:codeChallenge ? @"code" : @"token"],
                             [NSURLQueryItem queryItemWithName:@"disable_signup" value:@"true"],
                             // Following params only apply if verifier is supplied
                             codeChallenge ? [NSURLQueryItem queryItemWithName:@"code_challenge" value:codeChallenge] : nil,
                             [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
                             nil
                             ];
    return components.URL;
}

+ (NSURL *)defaultTokenAuthenticationRedirectURLWithClientIdentifier:(NSString *const)clientIdentifier
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"db-%@://2/token", clientIdentifier]];
}

+ (nullable NSString *)accessTokenFromURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL
{
    NSString *accessToken = nil;
    if ([url.absoluteString hasPrefix:redirectURL.absoluteString]) {
        NSString *const fragment = url.fragment;
        NSURLComponents *const components = [NSURLComponents new];
        components.query = fragment;
        for (NSURLQueryItem *const item in components.queryItems) {
            if ([item.name isEqualToString:@"access_token"]) {
                accessToken = item.value;
                break;
            }
        }
    }
    return accessToken;
}

+ (NSString *)accessTokenFromURL:(NSURL *const)url withClientIdentifier:(NSString *const)clientIdentifier
{
    return [self accessTokenFromURL:url withRedirectURL:[self defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier]];
}

+ (void)accessTokenFromCode:(NSString *const)code
       withClientIdentifier:(NSString *const)clientIdentifier
               codeVerifier:(NSString *const)codeVerifier
                redirectURL:(NSURL *const)redirectURL
                 completion:(void (^const)(NSString *_Nullable, NSError *_Nullable))completion
{
    // https://www.dropbox.com/developers/documentation/http/documentation#oauth2-token
    // https://bit.ly/3fKbMd3
    
    _performAPIRequest(nil,
                       ^NSURLRequest *{
        NSMutableURLRequest *const request = _apiRequest(@"/oauth2/token", nil, nil);
        NSURLComponents *const components = [NSURLComponents new];
        components.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"grant_type" value:@"authorization_code"],
            [NSURLQueryItem queryItemWithName:@"code" value:code],
            [NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
            [NSURLQueryItem queryItemWithName:@"code_verifier" value:codeVerifier],
            [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURL.absoluteString],
        ];
        request.HTTPBody = [components.query dataUsingEncoding:NSUTF8StringEncoding];
        [request addValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
        return request;
    },
                       ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        completion(parsedResponse[@"access_token"], error);
    });
}

+ (BOOL)isAuthenticationErrorURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL
{
    // when the user presses the cancel button on the website, this URL is returned:
    // db-XXX://2/token#error_description=The+user+chose+not+to+give+your+app+access+to+their+Dropbox+account.&error=access_denied
    if ([url.absoluteString hasPrefix:redirectURL.absoluteString]) {
        NSString *const fragment = url.fragment;
        NSURLComponents *const components = [NSURLComponents new];
        components.query = fragment;
        for (NSURLQueryItem *const item in components.queryItems) {
            if ([item.name isEqualToString:@"error"]) {
                return YES;
            }
        }
    }
    return NO;
}

+ (BOOL)isAuthenticationErrorURL:(NSURL *const)url withClientIdentifier:(NSString *const)clientIdentifier
{
    return [self isAuthenticationErrorURL:url withRedirectURL:[self defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier]];
}

+ (NSURL *)dropboxAppAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier
                                              codeVerifier:(nullable NSString *const)codeVerifier
{
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L288-L303
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L274-L282
    
    NSURLComponents *const components = [NSURLComponents componentsWithString:@"dbapi-2://1/connect"];
    
    NSString *stateString;
    NSString *extraQueryParams = nil;
    if (codeVerifier) {
        NSString *const codeChallenge = _codeChallengeFromCodeVerifier(codeVerifier);
        stateString = [NSString stringWithFormat:@"oauth2code:%@:S256:", codeChallenge];
        
        NSURLComponents *const extraComponents = [NSURLComponents new];
        extraComponents.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"code_challenge" value:codeChallenge],
            [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
            [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
        ];
        extraQueryParams = extraComponents.query;
    } else {
        NSString *const nonce = [[NSUUID UUID] UUIDString];
        stateString = [NSString stringWithFormat:@"oauth2:%@", nonce];
    }
    
    components.queryItems = [NSArray arrayWithObjects:
                             [NSURLQueryItem queryItemWithName:@"k" value:clientIdentifier],
                             [NSURLQueryItem queryItemWithName:@"s" value:@""],
                             [NSURLQueryItem queryItemWithName:@"state" value:stateString],
                             // Following params only apply if verifier is supplied https://bit.ly/37OmYmh
                             extraQueryParams ? [NSURLQueryItem queryItemWithName:@"extra_query_params" value:extraQueryParams] : nil,
                             nil
                             ];
    return components.URL;
}

+ (nullable NSString *)accessTokenFromDropboxAppAuthenticationURL:(NSURL *const)url
{
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L360-L383
    
    NSString *accessToken = nil;
    if ([url.scheme hasPrefix:@"db-"] && [url.host isEqualToString:@"1"] && [url.path isEqualToString:@"/connect"]) {
        NSURLComponents *const components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"oauth_token_secret"] && queryItem.value.length > 0) {
                accessToken = queryItem.value;
                break;
            }
        }
    }
    return accessToken;
}

+ (void)revokeCredential:(TJDropboxCredential *const)credential withCallback:(void (^const)(BOOL success, NSError *_Nullable error))completion
{
    // https://www.dropbox.com/developers/documentation/http/documentation#auth-token-revoke
    
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _apiRequest(@"/2/auth/token/revoke", credential.accessToken, nil);
    },
                       ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        completion(error == nil, error);
    });
}

#pragma mark - Generic

static NSString *_asciiEncodeString(NSString *const string)
{
    // Inspired by: https://github.com/dropbox/SwiftyDropbox/blob/6747041b04e337efe0de8f3be14acaf3b6d6d19b/Source/Client.swift#L90-L104
    // Useful: http://stackoverflow.com/a/1775880
    // Useful: https://www.objc.io/issues/9-strings/unicode/
    
    const NSUInteger stringLength = string.length;
    NSMutableString *const result = string ? [NSMutableString stringWithCapacity:stringLength] : nil;
    
    [string enumerateSubstringsInRange:NSMakeRange(0, stringLength) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
        const unichar character = [substring characterAtIndex:0];
        NSString *stringToAppend = nil;
        if (character > 127) {
            stringToAppend = [NSString stringWithFormat:@"\\u%04x", character];
        } else {
            stringToAppend = substring;
        }
        [result appendString:stringToAppend];
    }];
    
    return result;
}

static NSString * _parameterStringForParameters(NSDictionary<NSString *, id> *parameters)
{
    NSString *parameterString = nil;
    if (parameters.count > 0) {
        NSError *error = nil;
        NSData *const parameterData = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&error];
        if (error) {
            NSLog(@"[TJDropbox] - Error in %s: %@", __PRETTY_FUNCTION__, error);
        } else {
            parameterString = [[NSString alloc] initWithData:parameterData encoding:NSUTF8StringEncoding];
            
            // Ugh http://stackoverflow.com/a/24807307
            // Asian characters are formatted as ASCII using +asciiEncodeString:, which adds a leading '\'.
            // NSJSONSerialization likes to turn '\' into '\\', which Dropbox doesn't tolerate.
            // This is a gross way of fixing it, but it works.
            // Sucks because we have to round trip from dictionary -> data -> string -> data in a lot of cases.
            parameterString = [parameterString stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
        }
    }
    return parameterString;
}

static NSMutableURLRequest *_baseRequest(NSString *const baseURLString, NSString *const path, NSString *const accessToken)
{
    NSURLComponents *const components = [[NSURLComponents alloc] initWithString:baseURLString];
    components.path = path;
    
    NSMutableURLRequest *const request = [[NSMutableURLRequest alloc] initWithURL:components.URL];
    request.HTTPMethod = @"POST";
    
    if (accessToken) {
        NSString *const authorization = [NSString stringWithFormat:@"Bearer %@", accessToken];
        [request addValue:authorization forHTTPHeaderField:@"Authorization"];
    }
    
#if defined(__IPHONE_15_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_15_0
    if (@available(iOS 15.0, *)) {
        request.attribution = NSURLRequestAttributionUser;
    }
#endif
    
    return request;
}

static NSMutableURLRequest *_apiRequest(NSString *const path, NSString *const accessToken, NSDictionary<NSString *, id> *const parameters)
{
    NSMutableURLRequest *const request = _baseRequest(@"https://api.dropboxapi.com", path, accessToken);
    request.HTTPBody = [_parameterStringForParameters(parameters) dataUsingEncoding:NSUTF8StringEncoding];
    
    if (request.HTTPBody != nil) {
        [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    
    return request;
}

static NSMutableURLRequest *_contentRequest(NSString *const path, NSString *const accessToken, NSDictionary<NSString *, id> *const parameters)
{
    NSMutableURLRequest *const request = _baseRequest(@"https://content.dropboxapi.com", path, accessToken);
    NSString *const parameterString = _parameterStringForParameters(parameters);
    [request setValue:parameterString forHTTPHeaderField:@"Dropbox-API-Arg"];
    return request;
}

static TJDropboxURLSessionTaskDelegate *_taskDelegate()
{
    static TJDropboxURLSessionTaskDelegate *taskDelegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        taskDelegate = [TJDropboxURLSessionTaskDelegate new];
    });
    return taskDelegate;
}

static NSURLSession *_session()
{
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TJDropboxURLSessionTaskDelegate *taskDelegate = _taskDelegate();
        NSURLSessionConfiguration *const configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.shouldUseExtendedBackgroundIdleMode = YES; // Allows requests to run better when the app is backgrounded https://twitter.com/BigZaphod/status/1164977540479553543
        session = [NSURLSession sessionWithConfiguration:configuration delegate:taskDelegate delegateQueue:taskDelegate.serialOperationQueue];
    });
    return session;
}

// This queue must be used when accessing the list of tasks (+[tasks] method).
// This ensures that the hash tables is only accessed by one thread at once.
static void _performBlockWithTasks(void (^block)(NSHashTable<NSURLSessionTask *> *tasks))
{
    static dispatch_queue_t tasksQueue;
    static NSHashTable<NSURLSessionTask *> *hashTable;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tasksQueue = dispatch_queue_create("TJDropbox Tasks Queue", DISPATCH_QUEUE_SERIAL);
        hashTable = [NSHashTable weakObjectsHashTable];
    });
    dispatch_async(tasksQueue, ^{
        block(hashTable);
    });
}

static void _addTask(TJDropboxCredential *credential,
                     NSURLSessionTask *(^taskBlock)(void)) // TODO: Credential error block param
{
    // TODO: Validate that credential expiration.
    NSURLSessionTask *task = taskBlock();
    _performBlockWithTasks(^(NSHashTable<NSURLSessionTask *> *tasks) {
        [tasks addObject:task];
    });
    [task resume];
}

static void _performAPIRequest(TJDropboxCredential *credential, NSURLRequest *(^requestBlock)(void), void (^const completion)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))
{
    _addTask(credential, ^NSURLSessionTask *{
        return [_session() dataTaskWithRequest:requestBlock() completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            _processResult(data, response, &error, &parsedResult);
            completion(parsedResult, error);
        }];
    });
}

static NSData *_resultDataForContentRequestResponse(NSURLResponse *const response)
{
    NSHTTPURLResponse *const httpURLResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    NSString *resultString;
    static NSString *const kDropboxAPIResultHeaderFieldKey = @"Dropbox-API-Result";
    if (@available(iOS 13.0, macOS 10.15, *)) {
        resultString = [httpURLResponse valueForHTTPHeaderField:kDropboxAPIResultHeaderFieldKey];
    } else {
        resultString = httpURLResponse.allHeaderFields[kDropboxAPIResultHeaderFieldKey];
    }
    NSData *const resultData = [resultString dataUsingEncoding:NSUTF8StringEncoding];
    return resultData;
}

static BOOL _processResult(NSData *const jsonData, NSURLResponse *const response, NSError **error, NSDictionary **parsedResult)
{
    NSString *errorString = nil;
    if (jsonData.length > 0) {
        id result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        if ([result isKindOfClass:[NSDictionary class]]) {
            *parsedResult = result;
        } else {
            errorString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
    }
    
    // Things leading to errors
    // 1. error returned to this block
    // 2. dropboxAPIErrorDictionary populated
    // 3. Status code >= 400
    // 4. errorString populated
    
    NSHTTPURLResponse *const httpURLResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    const NSInteger statusCode = [httpURLResponse statusCode];
    NSDictionary *const dropboxAPIErrorDictionary = [*parsedResult objectForKey:@"error"];
    
    if (!*error) {
        if (statusCode >= 400 || dropboxAPIErrorDictionary || (!*parsedResult && statusCode != 200)) {
            NSMutableDictionary *const userInfo = [NSMutableDictionary new];
            if (response) {
                [userInfo setObject:response forKey:TJDropboxErrorUserInfoKeyResponse];
            }
            if ([dropboxAPIErrorDictionary isKindOfClass:[NSDictionary class]]) {
                [userInfo setObject:dropboxAPIErrorDictionary forKey:TJDropboxErrorUserInfoKeyDropboxError];
            }
            if (errorString) {
                [userInfo setObject:errorString forKey:TJDropboxErrorUserInfoKeyErrorString];
            }
            *error = [NSError errorWithDomain:TJDropboxErrorDomain code:0 userInfo:userInfo];
        }
    }
    
    return *error == nil;
}

#pragma mark - Account Info

+ (void)getAccountInformationWithCredential:(TJDropboxCredential *)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _apiRequest(@"/2/users/get_current_account", credential.accessToken, nil);
    },
                       completion);
}

#pragma mark - File Inspection

static NSURLRequest *_listFolderRequest(NSString *const filePath, NSString *const accessToken, NSString *_Nullable const cursor, const BOOL includeDeleted)
{
    NSString *const urlPath = cursor.length > 0 ? @"/2/files/list_folder/continue" : @"/2/files/list_folder";
    NSMutableDictionary *const parameters = [NSMutableDictionary new];
    if (cursor.length > 0) {
        [parameters setObject:cursor forKey:@"cursor"];
    } else {
        [parameters setObject:_asciiEncodeString(filePath) forKey:@"path"];
        if (includeDeleted) {
            [parameters setObject:@YES forKey:@"include_deleted"];
        }
    }
    if (!cursor) {
        [parameters setObject:@(2000) forKey:@"limit"];
    }
    return _apiRequest(urlPath, accessToken, parameters);
}

+ (void)listFolderWithPath:(NSString *const)path credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    [self listFolderWithPath:path credential:credential cursor:nil includeDeleted:NO accumulatedFiles:nil completion:completion];
}

+ (void)listFolderWithPath:(NSString *const)path cursor:(nullable NSString *const)cursor includeDeleted:(const BOOL)includeDeleted credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    [self listFolderWithPath:path credential:credential cursor:cursor includeDeleted:includeDeleted accumulatedFiles:nil completion:completion];
}

+ (void)listFolderWithPath:(NSString *const)path credential:(TJDropboxCredential *const)credential cursor:(NSString *const)cursor includeDeleted:(const BOOL)includeDeleted accumulatedFiles:(NSArray *const)accumulatedFiles completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _listFolderRequest(path, credential.accessToken, cursor, includeDeleted);
    },
                       ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        if (!error) {
            NSArray *const files = [parsedResponse objectForKey:@"entries"];
            NSArray *newlyAccumulatedFiles;
            
            if ([files isKindOfClass:[NSArray class]]) {
                newlyAccumulatedFiles = accumulatedFiles.count > 0 ? [accumulatedFiles arrayByAddingObjectsFromArray:files] : files;
            } else {
                newlyAccumulatedFiles = nil;
            }
            
            id hasMoreObject = [parsedResponse objectForKey:@"has_more"];
            BOOL hasMore = [hasMoreObject respondsToSelector:@selector(boolValue)] ? [hasMoreObject boolValue] : NO;
            NSString *const cursor = [parsedResponse objectForKey:@"cursor"];
            
            if (hasMore) {
                if ([cursor isKindOfClass:[NSString class]]) {
                    // Fetch next page
                    [self listFolderWithPath:path credential:credential cursor:cursor includeDeleted:includeDeleted accumulatedFiles:newlyAccumulatedFiles completion:completion];
                } else {
                    // We can't load more without a cursor
                    completion(nil, nil, error);
                }
            } else {
                // All files fetched, finish.
                completion(newlyAccumulatedFiles, cursor, error);
            }
        } else {
            completion(nil, nil, error);
        }
    });
}

+ (void)getFileInfoAtPath:(NSString *const)remotePath credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable entry, NSError *_Nullable error))completion
{
    _performAPIRequest(credential, ^NSURLRequest *{
        return _apiRequest(@"/2/files/get_metadata", credential.accessToken,
                           @{
                               @"path" : _asciiEncodeString(remotePath)
                           });
    },
                       completion);
}

#pragma mark - File Manipulation

+ (NSURLRequest *)requestToDownloadFileAtPath:(NSString *const)path credential:(TJDropboxCredential *const)credential
{
    return _contentRequest(@"/2/files/download",
                           credential.accessToken,
                           @{
                               @"path": _asciiEncodeString(path)
                           });
}

+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self downloadFileAtPath:remotePath toPath:localPath credential:credential progressBlock:nil completion:completion];
}

+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath credential:(TJDropboxCredential *const)credential progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _addTask(credential, ^NSURLSessionTask *{
        NSURLRequest *const request = [self requestToDownloadFileAtPath:remotePath credential:credential];
        
        NSURLSessionDownloadTask *const task = [_session() downloadTaskWithRequest:request];
        
        [_taskDelegate() setProgressBlock:progressBlock
                          completionBlock:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            NSData *const resultData = _resultDataForContentRequestResponse(response);
            _processResult(resultData, response, &error, &parsedResult);
            
            if (!error && location) {
                NSFileManager *fileManager = [NSFileManager defaultManager];
                
                // remove file if it exists
                if ([fileManager fileExistsAtPath:localPath]) {
                    [fileManager removeItemAtPath:localPath error:&error];
                }
                if (!error) {
                    // Move file into place
                    [fileManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:localPath isDirectory:NO] error:&error];
                }
            }
            
            completion(parsedResult, error);
        }
                          forDownloadTask:task];
        return task;
    });
}

+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self uploadFileAtPath:localPath toPath:remotePath overwriteExisting:NO muteDesktopNotifications:NO credential:credential progressBlock:nil completion:completion];
}

+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting muteDesktopNotifications:(const BOOL)muteDesktopNotifications credential:(TJDropboxCredential *const)credential progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _addTask(credential, ^NSURLSessionTask *{
        NSMutableDictionary<NSString *, id> *const parameters = [NSMutableDictionary new];
        parameters[@"path"] = _asciiEncodeString(remotePath);
        if (overwriteExisting) {
            parameters[@"mode"] = @{@".tag": @"overwrite"};
        }
        if (muteDesktopNotifications) {
            parameters[@"mute"] = @YES;
        }
        NSURLRequest *const request = _contentRequest(@"/2/files/upload", credential.accessToken, parameters);
        
        NSURLSessionUploadTask *const task = [_session() uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:localPath isDirectory:NO]];
        
        [_taskDelegate() setProgressBlock:progressBlock
                          completionBlock:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            _processResult(data, response, &error, &parsedResult);
            
            completion(parsedResult, error);
        }
                              forDataTask:task];
        return task;
    });
}

+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self uploadLargeFileAtPath:localPath toPath:remotePath overwriteExisting:NO muteDesktopNotifications:NO credential:credential progressBlock:nil completion:completion];
}

+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting muteDesktopNotifications:(const BOOL)muteDesktopNotifications credential:(TJDropboxCredential *const)credential progressBlock:(void (^const _Nullable)(CGFloat))progressBlock completion:(nonnull void (^const)(NSDictionary * _Nullable, NSError * _Nullable))completion
{
    _addTask(credential, ^NSURLSessionTask *{
        NSMutableURLRequest *const request = _contentRequest(@"/2/files/upload_session/start", credential.accessToken, nil);
        [request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
        
        NSURLSessionTask *const task = [_session() dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            _processResult(data, response, &error, &parsedResult);
            
            NSString *const sessionIdentifier = parsedResult[@"session_id"];
            if (sessionIdentifier) {
                NSFileHandle *const fileHandle = [NSFileHandle fileHandleForReadingAtPath:localPath];
                
                unsigned long long fileSize = [fileHandle seekToEndOfFile];
                [fileHandle seekToFileOffset:0];
                
                _uploadChunk(fileHandle, fileSize, sessionIdentifier, remotePath, overwriteExisting, muteDesktopNotifications, credential, progressBlock, completion);
            } else {
                completion(parsedResult, error);
            }
        }];
        
        return task;
    });
}

static void _uploadChunk(NSFileHandle *const fileHandle, unsigned long long fileSize, NSString *const sessionIdentifier, NSString *const remotePath, const BOOL overwriteExisting, const BOOL muteDesktopNotifications, TJDropboxCredential *credential, void (^progressBlock)(CGFloat progress), void (^completion)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))
{
    _addTask(credential, ^NSURLSessionTask *{
        const unsigned long long offset = fileHandle.offsetInFile;
        static const NSUInteger kChunkSize = 10 * 1024 * 1024; // use 10 MB - same as the official Obj-C Dropbox SDK
        NSData *const chunk = [fileHandle readDataOfLength:kChunkSize];
        NSUInteger chunkLength = [chunk length];
        const BOOL isLastChunk = chunkLength < kChunkSize;
        
        NSMutableURLRequest *const request = _contentRequest(@"/2/files/upload_session/append_v2", credential.accessToken,
                                                             @{
                                                                 @"cursor": @{
                                                                         @"session_id": sessionIdentifier,
                                                                         @"offset": @(offset)
                                                                 },
                                                                 @"close": @(isLastChunk)
                                                             });
        [request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
        
        NSURLSessionUploadTask *const task = [_session() uploadTaskWithRequest:request fromData:chunk];
        
        void (^totalProgressBlock)(CGFloat);
        if (progressBlock) {
            totalProgressBlock = ^(CGFloat progress) {
                unsigned long long totalBytesRead = offset + chunkLength * progress;
                CGFloat totalProgress = (CGFloat)totalBytesRead / fileSize;
                progressBlock(totalProgress);
            };
        } else {
            totalProgressBlock = nil;
        }
        [_taskDelegate() setProgressBlock:totalProgressBlock
                          completionBlock:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            _processResult(data, response, &error, &parsedResult);
            
            if (error && [(NSHTTPURLResponse *)response statusCode] != 200) {
                // Error encountered
                completion(parsedResult, error);
            } else if (isLastChunk) {
                // Finish the upload
                _finishLargeUpload(fileHandle, sessionIdentifier, remotePath, overwriteExisting, muteDesktopNotifications, credential, completion);
            } else {
                // Upload next chunk
                _uploadChunk(fileHandle, fileSize, sessionIdentifier, remotePath, overwriteExisting, muteDesktopNotifications, credential, progressBlock, completion);
            }
        }
                              forDataTask:task];
        return task;
    });
}

static void _finishLargeUpload(NSFileHandle *const fileHandle, NSString *const sessionIdentifier, NSString *const remotePath, const BOOL overwriteExisting, const BOOL muteDesktopNotifications, TJDropboxCredential *const credential, void (^completion)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))
{
    _addTask(credential, ^NSURLSessionTask *{
        NSNumber *const offset = @(fileHandle.offsetInFile);
        
        NSMutableDictionary *const commit = [NSMutableDictionary new];
        commit[@"path"] = _asciiEncodeString(remotePath);
        if (overwriteExisting) {
            commit[@"mode"] = @{@".tag": @"overwrite"};
        }
        if (muteDesktopNotifications) {
            commit[@"mute"] = @YES;
        }
        NSMutableURLRequest *const request = _contentRequest(@"/2/files/upload_session/finish", credential.accessToken,
                                                             @{
                                                                 @"cursor": @{
                                                                         @"session_id": sessionIdentifier,
                                                                         @"offset": offset
                                                                 },
                                                                 @"commit": commit
                                                             });
        [request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
        
        NSURLSessionTask *const task = [_session() dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            _processResult(data, response, &error, &parsedResult);
            completion(parsedResult, error);
        }];
        return task;
    });
}

+ (void)createFolderAtPath:(NSString *const)path credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _apiRequest(@"/2/files/create_folder", credential.accessToken,
                           @{
                               @"path": _asciiEncodeString(path)
                           });
    },
                       completion);
}

+ (void)saveContentsOfURL:(NSURL *const)url toPath:(NSString *const)path credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _apiRequest(@"/2/files/save_url", credential.accessToken,
                           @{
                               @"url": url.absoluteString,
                               @"path": path
                           });
    },
                       completion);
}

+ (void)moveFileAtPath:(NSString *const)fromPath toPath:(NSString *const)toPath credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _apiRequest(@"/2/files/move_v2", credential.accessToken,
                           @{
                               @"from_path" : _asciiEncodeString(fromPath),
                               @"to_path" : _asciiEncodeString(toPath)
                           });
    },
                       completion);
}

+ (void)deleteFileAtPath:(NSString *const)path credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _performAPIRequest(credential, ^NSURLRequest *{
        return _apiRequest(@"/2/files/delete_v2", credential.accessToken,
                           @{
                               @"path": _asciiEncodeString(path)
                           });
    },
                       completion);
}

+ (NSURLRequest *)requestToDownloadThumbnailAtPath:(NSString *const)path size:(const TJDropboxThumbnailSize)thumbnailSize credential:(TJDropboxCredential *const)credential
{
    // https://www.dropbox.com/developers/documentation/http/documentation#files-get_thumbnail
    NSString *thumbnailSizeValue = nil;
    switch (thumbnailSize) {
        case TJDropboxThumbnailSize32Square:
            thumbnailSizeValue = @"w32h32";
            break;
        case TJDropboxThumbnailSize64Square:
            thumbnailSizeValue = @"w64h64";
            break;
        case TJDropboxThumbnailSize128Square:
            thumbnailSizeValue = @"w128h128";
            break;
        case TJDropboxThumbnailSize640x480:
            thumbnailSizeValue = @"w640h480";
            break;
        case TJDropboxThumbnailSize1024x768:
            thumbnailSizeValue = @"w1024h768";
            break;
    }
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    parameters[@"path"] = _asciiEncodeString(path);
    if (thumbnailSizeValue) {
        parameters[@"size"] = thumbnailSizeValue;
    }
    return _contentRequest(@"/2/files/get_thumbnail", credential.accessToken, parameters);
}

+ (void)downloadThumbnailAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath size:(const TJDropboxThumbnailSize)thumbnailSize credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary * _Nullable, NSError * _Nullable))completion
{
    _addTask(credential, ^NSURLSessionTask *{
        NSURLRequest *const request = [self requestToDownloadThumbnailAtPath:remotePath size:thumbnailSize credential:credential];
        
        NSURLSessionDownloadTask *const task = [_session() downloadTaskWithRequest:request];
        
        [_taskDelegate() setProgressBlock:nil
                          completionBlock:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            NSData *const resultData = _resultDataForContentRequestResponse(response);
            _processResult(resultData, response, &error, &parsedResult);
            
            if (!error && location) {
                NSFileManager *fileManager = [NSFileManager defaultManager];
                
                // remove file if it exists
                if ([fileManager fileExistsAtPath:localPath]) {
                    [fileManager removeItemAtPath:localPath error:&error];
                }
                if (!error) {
                    // Move file into place
                    [fileManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:localPath isDirectory:NO] error:&error];
                }
            }
            
            completion(parsedResult, error);
        }
                          forDownloadTask:task];
        return task;
    });
}

#pragma mark - Search

+ (void)searchForFilesAtPath:(NSString *const)path matchingQuery:(NSString *const)query options:(NSDictionary *const)additionalOptions credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSArray *_Nullable entries, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        // https://www.dropbox.com/developers/documentation/http/documentation?oref=e#files-search
        NSMutableDictionary *const options = [NSMutableDictionary dictionaryWithObjectsAndKeys:path, @"path", nil];
        [options addEntriesFromDictionary:additionalOptions];
        return _apiRequest(@"/2/files/search_v2", credential.accessToken,
                           @{
                               @"query": _asciiEncodeString(query),
                               @"options": options
                           });
    },
                       ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        completion(parsedResponse[@"matches"], error);
    });
}

#pragma mark - Sharing

+ (void)getSharedLinkForFileAtPath:(NSString *const)path credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSString *_Nullable urlString))completion
{
    [self getSharedLinkForFileAtPath:path linkType:TJDropboxSharedLinkTypeDefault uploadOrSaveInProgress:NO credential:credential completion:completion];
}

+ (void)getSharedLinkForFileAtPath:(NSString *const)path linkType:(const TJDropboxSharedLinkType)linkType uploadOrSaveInProgress:(const BOOL)uploadOrSaveInProgress credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSString *_Nullable urlString))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        // NOTE: create_shared_link has been deprecated, will likely be removed by Dropbox at some point. https://goo.gl/ZSrxRN
        NSString *const requestPath = linkType == TJDropboxSharedLinkTypeShort || uploadOrSaveInProgress ? @"/2/sharing/create_shared_link" : @"/2/sharing/create_shared_link_with_settings";
        NSMutableDictionary *parameters = [NSMutableDictionary new];
        [parameters setObject:_asciiEncodeString(path) forKey:@"path"];
        if (linkType == TJDropboxSharedLinkTypeShort) {
            [parameters setObject:@YES forKey:@"short_url"];
        }
        if (uploadOrSaveInProgress) {
            if (linkType == TJDropboxSharedLinkTypeDirect) {
                NSLog(@"[TJDropbox] - Warning in %s: uploadOrSaveInProgress is not compatible with TJDropboxSharedLinkTypeDirect. Parameter is being ignored.", __PRETTY_FUNCTION__);
            } else {
                [parameters setObject:@"file" forKey:@"pending_upload"];
            }
        }
        return _apiRequest(requestPath, credential.accessToken, parameters);
    },
                       ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        NSString *urlString = parsedResponse[@"url"];
        if (urlString.length == 0) {
            urlString = parsedResponse[@"error"][@"shared_link_already_exists"][@"metadata"][@"url"];
        }
        if (urlString.length > 0) {
            NSURLComponents *const components = [NSURLComponents componentsWithString:urlString];
            if (linkType == TJDropboxSharedLinkTypeDirect) {
                components.host = @"dl.dropboxusercontent.com";
            } else if (linkType == TJDropboxSharedLinkTypeDefault) {
                components.path = components.path.stringByDeletingLastPathComponent;
                components.host = [components.host stringByReplacingOccurrencesOfString:@"www." withString:@""];
            }
            components.queryItems = nil; // the ?dl=0 that Dropbox appends doesn't seem strictly necessary.
            urlString = components.URL.absoluteString;
        }
        completion(urlString);
    });
}

#pragma mark - Users

+ (void)getSpaceUsageForUserWithCredential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _apiRequest(@"/2/users/get_space_usage", credential.accessToken, nil);
    },
                       completion);
}

#pragma mark - Request Management

+ (void)cancelAllRequests
{
    _performBlockWithTasks(^(NSHashTable<NSURLSessionTask *> *tasks) {
        for (NSURLSessionTask *const task in tasks) {
            [task cancel];
        }
    });
}

@end

@implementation NSError (TJDropbox)

- (BOOL)tj_isPathNotFoundError
{
    BOOL isPathNotFoundError = NO;
    if ([self.domain isEqualToString:TJDropboxErrorDomain]) {
        NSDictionary *const dropboxErrorDictionary = self.userInfo[TJDropboxErrorUserInfoKeyDropboxError];
        NSString *const tag = dropboxErrorDictionary[@".tag"];
        if ([tag isEqualToString:@"path"] || [tag isEqualToString:@"path_lookup"]) {
            NSString *const pathTag = dropboxErrorDictionary[tag][@".tag"];
            if ([pathTag isEqualToString:@"not_found"]) {
                isPathNotFoundError = YES;
            }
        }
    }
    return isPathNotFoundError;
}

// Happens when token isn't recognized (401)
- (BOOL)tj_isInvalidAccessTokenError
{
    BOOL isInvalidAccessTokenError = NO;
    if ([self.domain isEqualToString:TJDropboxErrorDomain]) {
        NSDictionary *const dropboxErrorDictionary = self.userInfo[TJDropboxErrorUserInfoKeyDropboxError];
        NSString *const tag = dropboxErrorDictionary[@".tag"];
        if ([tag isEqualToString:@"invalid_access_token"]) {
            isInvalidAccessTokenError = YES;
        }
    }
    return isInvalidAccessTokenError;
}

// Happens when access token is expired, needs refresh (401)
- (BOOL)tj_isExpiredAccessTokenError
{
    BOOL isInvalidAccessTokenError = NO;
    if ([self.domain isEqualToString:TJDropboxErrorDomain]) {
        NSDictionary *const dropboxErrorDictionary = self.userInfo[TJDropboxErrorUserInfoKeyDropboxError];
        NSString *const tag = dropboxErrorDictionary[@".tag"];
        if ([tag isEqualToString:@"expired_access_token"]) {
            isInvalidAccessTokenError = YES;
        }
    }
    return isInvalidAccessTokenError;
}

- (BOOL)tj_isInsufficientSpaceError
{
    BOOL isInsufficientSpaceError = NO;
    if ([self.domain isEqualToString:TJDropboxErrorDomain]) {
        NSDictionary *const dropboxErrorDictionary = self.userInfo[TJDropboxErrorUserInfoKeyDropboxError];
        NSString *const tag = dropboxErrorDictionary[@"reason"][@".tag"];
        if ([tag isEqualToString:@"insufficient_space"]) {
            isInsufficientSpaceError = YES;
        }
    }
    return isInsufficientSpaceError;
}

@end
