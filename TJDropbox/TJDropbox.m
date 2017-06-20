//
//  TJDropbox.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "TJDropbox.h"

NSString *const TJDropboxErrorDomain = @"TJDropboxErrorDomain";
NSString *const TJDropboxErrorUserInfoKeyResponse = @"response";
NSString *const TJDropboxErrorUserInfoKeyDropboxError = @"dropboxError";
NSString *const TJDropboxErrorUserInfoKeyErrorString = @"errorString";

@interface TJDropboxURLSessionTaskDelegate : NSObject <NSURLSessionDataDelegate, NSURLSessionDownloadDelegate>

@property (nonatomic, strong) NSMutableDictionary *progressBlocksForDataTasks;
@property (nonatomic, strong) NSMutableDictionary<NSURLSessionTask *, NSMutableData *> *accumulatedDataForDataTasks;
@property (nonatomic, strong) NSMutableDictionary *completionBlocksForDataTasks;

@property (nonatomic, strong) NSMutableDictionary *progressBlocksForDownloadTasks;
@property (nonatomic, strong) NSMutableDictionary *completionBlocksForDownloadTasks;

// This serial queue must be used for the following:
//   - as the NSURLSession delegateQueue
//   - when accessing the task delegate's block and accumulatedData dictionaries
// This ensures that these dictionaries are only accessed by one thread at once.
@property (nonatomic, strong) NSOperationQueue *serialOperationQueue;

@end

@implementation TJDropboxURLSessionTaskDelegate

- (instancetype)init
{
    if (self = [super init]) {
        self.progressBlocksForDataTasks = [NSMutableDictionary new];
        self.accumulatedDataForDataTasks = [NSMutableDictionary new];
        self.completionBlocksForDataTasks = [NSMutableDictionary new];
        
        self.progressBlocksForDownloadTasks = [NSMutableDictionary new];
        self.completionBlocksForDownloadTasks = [NSMutableDictionary new];
        
        NSOperationQueue *serialOperationQueue = [[NSOperationQueue alloc] init];
        // make serial
        serialOperationQueue.maxConcurrentOperationCount = 1;
        serialOperationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        self.serialOperationQueue = serialOperationQueue;
    }
    return self;
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
    void (^progressBlock)(CGFloat progress) = self.progressBlocksForDataTasks[task];
    
    if (progressBlock && totalBytesExpectedToSend > 0) {
        progressBlock((CGFloat)totalBytesSent / totalBytesExpectedToSend);
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    void (^progressBlock)(CGFloat progress) = self.progressBlocksForDownloadTasks[task];
    
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
    
    [self.progressBlocksForDataTasks removeObjectForKey:task];
    [self.accumulatedDataForDataTasks removeObjectForKey:task];
    [self.completionBlocksForDataTasks removeObjectForKey:task];
    [self.progressBlocksForDownloadTasks removeObjectForKey:task];
    [self.completionBlocksForDownloadTasks removeObjectForKey:task];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task didFinishDownloadingToURL:(NSURL *)location
{
    // Catches the case where the file was downloaded successfully.
    [self tryCompleteTask:task location:location data:nil];
}

- (void)tryCompleteTask:(NSURLSessionTask *const)task location:(NSURL *const)location data:(NSData *const)data
{
    void (^downloadCompletionBlock)(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) = self.completionBlocksForDownloadTasks[task];
    if (downloadCompletionBlock) {
        downloadCompletionBlock(location, task.response, task.error);
        [self.completionBlocksForDownloadTasks removeObjectForKey:task];
    } else {
        void (^dataCompletionBlock)(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) = self.completionBlocksForDataTasks[task];
        if (dataCompletionBlock) {
            dataCompletionBlock(self.accumulatedDataForDataTasks[task], task.response, task.error);
        }
    }
}

@end

@implementation TJDropbox

#pragma mark - Authentication

+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier redirectURL:(NSURL *const)redirectURL
{
    // https://www.dropbox.com/developers/documentation/http/documentation#auth
    
    NSURLComponents *const components = [NSURLComponents componentsWithURL:[NSURL URLWithString:@"https://www.dropbox.com/oauth2/authorize"] resolvingAgainstBaseURL:NO];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
        [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURL.absoluteString],
        [NSURLQueryItem queryItemWithName:@"response_type" value:@"token"],
        [NSURLQueryItem queryItemWithName:@"disable_signup" value:@"true"]
    ];
    return components.URL;
}

+ (NSURL *)defaultTokenAuthenticationRedirectURLWithClientIdentifier:(NSString *const)clientIdentifier
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"db-%@://2/token", clientIdentifier]];
}

+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier
{
    return [self tokenAuthenticationURLWithClientIdentifier:clientIdentifier redirectURL:[self defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier]];
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
{
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L288-L303
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L274-L282
    
    NSURLComponents *const components = [NSURLComponents componentsWithString:@"dbapi-2://1/connect"];
    NSString *const nonce = [[NSUUID UUID] UUIDString];
    NSString *const stateString = [NSString stringWithFormat:@"oauth2:%@", nonce];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"k" value:clientIdentifier],
        [NSURLQueryItem queryItemWithName:@"s" value:@""],
        [NSURLQueryItem queryItemWithName:@"state" value:stateString]
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

#pragma mark - Generic

+ (NSMutableURLRequest *)requestWithBaseURLString:(NSString *const)baseURLString path:(NSString *const)path accessToken:(NSString *const)accessToken
{
    NSURLComponents *const components = [[NSURLComponents alloc] initWithString:baseURLString];
    components.path = path;
    
    NSMutableURLRequest *const request = [[NSMutableURLRequest alloc] initWithURL:components.URL];
    request.HTTPMethod = @"POST";
    
    if (accessToken) {
        NSString *const authorization = [NSString stringWithFormat:@"Bearer %@", accessToken];
        [request addValue:authorization forHTTPHeaderField:@"Authorization"];
    }
    
    return request;
}

+ (NSString *)parameterStringForParameters:(NSDictionary<NSString *, NSString *> *)parameters
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

+ (NSMutableURLRequest *)apiRequestWithPath:(NSString *const)path accessToken:(NSString *const)accessToken parameters:(NSDictionary<NSString *, NSString *> *const)parameters
{
    NSMutableURLRequest *const request = [self requestWithBaseURLString:@"https://api.dropboxapi.com" path:path accessToken:accessToken];
    request.HTTPBody = [[self parameterStringForParameters:parameters] dataUsingEncoding:NSUTF8StringEncoding];
    
    if (request.HTTPBody != nil) {
        [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    
    return request;
}

+ (NSMutableURLRequest *)contentRequestWithPath:(NSString *const)path accessToken:(NSString *const)accessToken parameters:(NSDictionary<NSString *, NSString *> *const)parameters
{
    NSMutableURLRequest *const request = [self requestWithBaseURLString:@"https://content.dropboxapi.com" path:path accessToken:accessToken];
    NSString *const parameterString = [self parameterStringForParameters:parameters];
    [request setValue:parameterString forHTTPHeaderField:@"Dropbox-API-Arg"];
    return request;
}

+ (TJDropboxURLSessionTaskDelegate *)taskDelegate
{
    static TJDropboxURLSessionTaskDelegate *taskDelegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        taskDelegate = [[TJDropboxURLSessionTaskDelegate alloc] init];
    });
    return taskDelegate;
}

+ (NSURLSession *)session
{
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TJDropboxURLSessionTaskDelegate *taskDelegate = [self taskDelegate];
        session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration] delegate:taskDelegate delegateQueue:taskDelegate.serialOperationQueue];
    });
    return session;
}

+ (NSHashTable<NSURLSessionTask *> *)_tasks
{
    static NSHashTable<NSURLSessionTask *> *hashTable = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hashTable = [NSHashTable weakObjectsHashTable];
    });
    return hashTable;
}

// This queue must be used when accessing the list of tasks (+[tasks] method).
// This ensures that the hash tables is only accessed by one thread at once.
+ (NSOperationQueue *)tasksOperationQueue
{
    static NSOperationQueue *tasksOperationQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tasksOperationQueue = [[NSOperationQueue alloc] init];
        tasksOperationQueue.maxConcurrentOperationCount = 1;
        tasksOperationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
    });
    return tasksOperationQueue;
}

+ (void)addTask:(NSURLSessionTask *)task
{
    [[self tasksOperationQueue] addOperationWithBlock:^{
        [[self _tasks] addObject:task];
    }];
}

+ (void)performAPIRequest:(NSURLRequest *)request withCompletion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLSessionTask *const task = [[self session] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *parsedResult = nil;
        [self processResultJSONData:data response:response error:&error parsedResult:&parsedResult];
        completion(parsedResult, error);
    }];
    [self addTask:task];
    [task resume];
}

+ (NSData *)resultDataForContentRequestResponse:(NSURLResponse *const)response
{
    NSHTTPURLResponse *const httpURLResponse = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
    NSString *const resultString = httpURLResponse.allHeaderFields[@"Dropbox-API-Result"];
    NSData *const resultData = [resultString dataUsingEncoding:NSUTF8StringEncoding];
    return resultData;
}

+ (BOOL)processResultJSONData:(NSData *const)data response:(NSURLResponse *const)response error:(inout NSError **)error parsedResult:(out NSDictionary **)parsedResult
{
    NSString *errorString = nil;
    if (data.length > 0) {
        id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([result isKindOfClass:[NSDictionary class]]) {
            *parsedResult = result;
        } else {
            errorString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
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
        if (statusCode >= 400 || dropboxAPIErrorDictionary || !*parsedResult) {
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

+ (NSString *)asciiEncodeString:(NSString *const)string
{
    // Inspired by: https://github.com/dropbox/SwiftyDropbox/blob/6747041b04e337efe0de8f3be14acaf3b6d6d19b/Source/Client.swift#L90-L104
    // Useful: http://stackoverflow.com/a/1775880
    // Useful: https://www.objc.io/issues/9-strings/unicode/
    
    NSMutableString *const result = string ? [NSMutableString new] : nil;
    
    [string enumerateSubstringsInRange:NSMakeRange(0, string.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString * _Nullable substring, NSRange substringRange, NSRange enclosingRange, BOOL * _Nonnull stop) {
        const unichar character = [substring characterAtIndex:0];
        NSString *stringToAppend = nil;
        if (character > 127) {
            stringToAppend = [NSString stringWithFormat:@"\\u%04x", character];
        } else {
            stringToAppend = substring;
        }
        if (stringToAppend) {
            [result appendString:stringToAppend];
        }
    }];
    
    return result;
}

#pragma mark - Token Migration

+ (void)migrateV1TokenToV2Token:(NSString *const)accessToken accessTokenSecret:(NSString *const)accessTokenSecret appKey:(NSString *const)appKey appSecret:(NSString *const)appSecret completion:(void (^const)(NSString *_Nullable, NSError *_Nullable))completion
{
    // https://github.com/dropbox/dropbox-sdk-obj-c/blob/3769fbacb0b458de7c20db08edba6ca21c54b650/Source/ObjectiveDropboxOfficial/Shared/Handwritten/OAuth/DBSDKKeychain.m#L363-L453
    // https://www.dropbox.com/developers/documentation/http/documentation#auth-token-from_oauth1
    
    NSMutableURLRequest *const request = [self apiRequestWithPath:@"/2/auth/token/from_oauth1"
                                                      accessToken:nil
                                                       parameters:@{@"oauth1_token": accessToken,
                                                                    @"oauth1_token_secret": accessTokenSecret}];
    
    // use basic auth
    NSString *authString = [[[NSString stringWithFormat:@"%@:%@", appKey, appSecret]
                             dataUsingEncoding:NSUTF8StringEncoding]
                            base64EncodedStringWithOptions:0];
    
    NSString *const authorization = [NSString stringWithFormat:@"Basic %@", authString];
    [request addValue:authorization forHTTPHeaderField:@"Authorization"];
    
    [self performAPIRequest:request withCompletion:^(NSDictionary *parsedResponse, NSError *error) {
        completion(parsedResponse[@"oauth2_token"], error);
    }];
}


#pragma mark - Account Info

+ (void)getAccountInformationWithAccessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/users/get_current_account" accessToken:accessToken parameters:nil];
    [self performAPIRequest:request withCompletion:completion];
}

#pragma mark - File Inspection

+ (NSURLRequest *)listFolderRequestWithPath:(NSString *const)filePath accessToken:(NSString *const)accessToken cursor:(nullable NSString *const)cursor includeDeleted:(const BOOL)includeDeleted
{
    NSString *const urlPath = cursor.length > 0 ? @"/2/files/list_folder/continue" : @"/2/files/list_folder";
    NSMutableDictionary *const parameters = [NSMutableDictionary new];
    if (cursor.length > 0) {
        [parameters setObject:cursor forKey:@"cursor"];
    } else {
        [parameters setObject:[self asciiEncodeString:filePath] forKey:@"path"];
        if (includeDeleted) {
            [parameters setObject:@YES forKey:@"include_deleted"];
        }
    }
    return [self apiRequestWithPath:urlPath accessToken:accessToken parameters:parameters];
}

+ (void)listFolderWithPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    [self listFolderWithPath:path cursor:nil includeDeleted:NO accessToken:accessToken completion:completion];
}

+ (void)listFolderWithPath:(NSString *const)path cursor:(nullable NSString *const)cursor includeDeleted:(const BOOL)includeDeleted accessToken:(NSString *const)accessToken completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    [self listFolderWithPath:path accessToken:accessToken cursor:cursor includeDeleted:includeDeleted accumulatedFiles:nil completion:completion];
}

+ (void)listFolderWithPath:(NSString *const)path accessToken:(NSString *const)accessToken cursor:(NSString *const)cursor includeDeleted:(const BOOL)includeDeleted accumulatedFiles:(NSArray *const)accumulatedFiles completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self listFolderRequestWithPath:path accessToken:accessToken cursor:cursor includeDeleted:includeDeleted];
    [self performAPIRequest:request withCompletion:^(NSDictionary *parsedResponse, NSError *error) {
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
                    [self listFolderWithPath:path accessToken:accessToken cursor:cursor includeDeleted:includeDeleted accumulatedFiles:newlyAccumulatedFiles completion:completion];
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
    }];
}

+ (void)getFileInfoAtPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable entry, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/get_metadata" accessToken:accessToken parameters:@{
        @"path" : [self asciiEncodeString:remotePath]
    }];
    
    [self performAPIRequest:request withCompletion:completion];
}

#pragma mark - File Manipulation

+ (NSURLRequest *)requestToDownloadFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken
{
    return [self contentRequestWithPath:@"/2/files/download" accessToken:accessToken parameters:@{
        @"path": [self asciiEncodeString:path]
    }];
}

+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self downloadFileAtPath:remotePath toPath:localPath accessToken:accessToken progressBlock:nil completion:completion];
}

+ (void)downloadFileAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath accessToken:(NSString *const)accessToken progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self requestToDownloadFileAtPath:remotePath accessToken:accessToken];
    
    NSURLSessionDownloadTask *const task = [[self session] downloadTaskWithRequest:request];
    
    TJDropboxURLSessionTaskDelegate *taskDelegate = [self taskDelegate];
    
    [taskDelegate.serialOperationQueue addOperationWithBlock:^{
        [[taskDelegate completionBlocksForDownloadTasks] setObject:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            NSData *const resultData = [self resultDataForContentRequestResponse:response];
            [self processResultJSONData:resultData response:response error:&error parsedResult:&parsedResult];
            
            if (!error && location) {
                NSFileManager *fileManager = [[NSFileManager alloc] init];
                
                // remove file if it exists
                if ([fileManager fileExistsAtPath:localPath]) {
                    [fileManager removeItemAtPath:localPath error:&error];
                }
                if (!error) {
                    // Move file into place
                    [fileManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:localPath] error:&error];
                }
            }
            
            completion(parsedResult, error);
        } forKey:task];
        if (progressBlock) {
            [[taskDelegate progressBlocksForDownloadTasks] setObject:progressBlock forKey:task];
        }
    }];
    
    [self addTask:task];
    [task resume];
}

+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self uploadFileAtPath:localPath toPath:remotePath overwriteExisting:NO accessToken:accessToken progressBlock:nil completion:completion];
}

+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting accessToken:(NSString *const)accessToken progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSMutableDictionary<NSString *, id> *const parameters = [NSMutableDictionary new];
    parameters[@"path"] = [self asciiEncodeString:remotePath];
    if (overwriteExisting) {
        parameters[@"mode"] = @{@".tag": @"overwrite"};
    }
    NSURLRequest *const request = [self contentRequestWithPath:@"/2/files/upload" accessToken:accessToken parameters:parameters];
    
    NSURLSessionTask *const task = [[self session] uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:localPath]];
    
    TJDropboxURLSessionTaskDelegate *taskDelegate = [self taskDelegate];
    
    [taskDelegate.serialOperationQueue addOperationWithBlock:^{
        [[taskDelegate completionBlocksForDataTasks] setObject:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            [self processResultJSONData:data response:response error:&error parsedResult:&parsedResult];
            
            completion(parsedResult, error);
        } forKey:task];
        if (progressBlock) {
            [[taskDelegate progressBlocksForDataTasks] setObject:progressBlock forKey:task];
        }
    }];
    
    [self addTask:task];
    [task resume];
}

+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self uploadLargeFileAtPath:localPath toPath:remotePath overwriteExisting:NO accessToken:accessToken progressBlock:nil completion:completion];
}

+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting accessToken:(nonnull NSString *const)accessToken progressBlock:(void (^const _Nullable)(CGFloat))progressBlock completion:(nonnull void (^const)(NSDictionary * _Nullable, NSError * _Nullable))completion
{
    NSMutableURLRequest *const request = [self contentRequestWithPath:@"/2/files/upload_session/start" accessToken:accessToken parameters:nil];
    [request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    
    NSURLSessionTask *const task = [[self session] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *parsedResult = nil;
        [self processResultJSONData:data response:response error:&error parsedResult:&parsedResult];
        
        NSString *const sessionIdentifier = parsedResult[@"session_id"];
        if (sessionIdentifier) {
            NSFileHandle *const fileHandle = [NSFileHandle fileHandleForReadingAtPath:localPath];
            
            unsigned long long fileSize = [fileHandle seekToEndOfFile];
            [fileHandle seekToFileOffset:0];
            
            [self uploadChunkFromFileHandle:fileHandle fileSize:fileSize sessionIdentifier:sessionIdentifier remotePath:remotePath overwriteExisting:overwriteExisting accessToken:accessToken progressBlock:progressBlock completion:completion];
        } else {
            completion(parsedResult, error);
        }
    }];
    [self addTask:task];
    [task resume];
}

+ (void)uploadChunkFromFileHandle:(NSFileHandle *const)fileHandle fileSize:(unsigned long long)fileSize sessionIdentifier:(NSString *const)sessionIdentifier remotePath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting accessToken:(NSString *const)accessToken progressBlock:(void (^const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    const unsigned long long offset = fileHandle.offsetInFile;
    static const NSUInteger kChunkSize = 10 * 1024 * 1024; // use 10 MB - same as the official Obj-C Dropbox SDK
    NSData *const chunk = [fileHandle readDataOfLength:kChunkSize];
    NSUInteger chunkLength = [chunk length];
    const BOOL isLastChunk = chunkLength < kChunkSize;
    
    NSMutableURLRequest *const request = [self contentRequestWithPath:@"/2/files/upload_session/append_v2" accessToken:accessToken parameters:@{
        @"cursor": @{
            @"session_id": sessionIdentifier,
            @"offset": @(offset)
        },
        @"close": @(isLastChunk)
    }];
    [request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    
    NSURLSessionTask *const task = [[self session] uploadTaskWithRequest:request fromData:chunk];
    
    TJDropboxURLSessionTaskDelegate *taskDelegate = [self taskDelegate];
    
    [taskDelegate.serialOperationQueue addOperationWithBlock:^{
        [[taskDelegate completionBlocksForDataTasks] setObject:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            [self processResultJSONData:data response:response error:&error parsedResult:&parsedResult];
            
            if (error && [(NSHTTPURLResponse *)response statusCode] != 200) {
                // Error encountered
                completion(parsedResult, error);
            } else if (isLastChunk) {
                // Finish the upload
                [self finishLargeUploadFromFileHandle:fileHandle sessionIdentifier:sessionIdentifier remotePath:remotePath overwriteExisting:overwriteExisting accessToken:accessToken completion:completion];
            } else {
                // Upload next chunk
                [self uploadChunkFromFileHandle:fileHandle fileSize:fileSize sessionIdentifier:sessionIdentifier remotePath:remotePath overwriteExisting:overwriteExisting accessToken:accessToken progressBlock:progressBlock completion:completion];
            }
        } forKey:task];
        if (progressBlock) {
            [[taskDelegate progressBlocksForDataTasks] setObject:^(CGFloat progress) {
                unsigned long long totalBytesRead = offset + chunkLength * progress;
                CGFloat totalProgress = (CGFloat)totalBytesRead / fileSize;
                progressBlock(totalProgress);
            } forKey:task];
        }
    }];

    [self addTask:task];
    [task resume];
}

+ (void)finishLargeUploadFromFileHandle:(NSFileHandle *const)fileHandle sessionIdentifier:(NSString *const)sessionIdentifier remotePath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSNumber *const offset = @(fileHandle.offsetInFile);
    
    NSMutableDictionary *const commit = [NSMutableDictionary new];
    commit[@"path"] = [self asciiEncodeString:remotePath];
    if (overwriteExisting) {
        commit[@"mode"] = @{@".tag": @"overwrite"};
    }
    NSMutableURLRequest *const request = [self contentRequestWithPath:@"/2/files/upload_session/finish" accessToken:accessToken parameters: @{
        @"cursor": @{
            @"session_id": sessionIdentifier,
            @"offset": offset
        },
        @"commit": commit
    }];
    [request addValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
    
    NSURLSessionTask *const task = [[self session] dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSDictionary *parsedResult = nil;
        [self processResultJSONData:data response:response error:&error parsedResult:&parsedResult];
        completion(parsedResult, error);
    }];
    [self addTask:task];
    [task resume];
}

+ (void)createFolderAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/create_folder"
                                               accessToken:accessToken
                                                parameters:@{@"path": [self asciiEncodeString:path]}];
    
    [self performAPIRequest:request withCompletion:completion];
}

+ (void)saveContentsOfURL:(NSURL *const)url toPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/save_url" accessToken:accessToken parameters:@{
        @"url": url.absoluteString,
        @"path": path
    }];
    
    [self performAPIRequest:request withCompletion:completion];
}

+ (void)moveFileAtPath:(NSString *const)fromPath toPath:(NSString *const)toPath accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/move" accessToken:accessToken parameters:@{
        @"from_path" : [self asciiEncodeString:fromPath],
        @"to_path" : [self asciiEncodeString:toPath]
    }];
    
    [self performAPIRequest:request withCompletion:completion];
}

+ (void)deleteFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/files/delete" accessToken:accessToken parameters:@{
        @"path": [self asciiEncodeString:path]
    }];
    [self performAPIRequest:request withCompletion:completion];
}

+ (NSURLRequest *)requestToDownloadThumbnailAtPath:(NSString *const)path size:(const TJDropboxThumbnailSize)thumbnailSize accessToken:(NSString *const )accessToken
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
    parameters[@"path"] = [self asciiEncodeString:path];
    if (thumbnailSizeValue) {
        parameters[@"size"] = thumbnailSizeValue;
    }
    return [self contentRequestWithPath:@"/2/files/get_thumbnail" accessToken:accessToken parameters:parameters];
}

+ (void)downloadThumbnailAtPath:(NSString *const)remotePath toPath:(NSString *const)localPath size:(const TJDropboxThumbnailSize)thumbnailSize accessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary * _Nullable, NSError * _Nullable))completion
{
    NSURLRequest *const request = [self requestToDownloadThumbnailAtPath:remotePath size:thumbnailSize accessToken:accessToken];
    
    NSURLSessionDownloadTask *const task = [[self session] downloadTaskWithRequest:request];
    
    TJDropboxURLSessionTaskDelegate *taskDelegate = [self taskDelegate];
    
    [taskDelegate.serialOperationQueue addOperationWithBlock:^{
        [[taskDelegate completionBlocksForDownloadTasks] setObject:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            NSData *const resultData = [self resultDataForContentRequestResponse:response];
            [self processResultJSONData:resultData response:response error:&error parsedResult:&parsedResult];
            
            if (!error && location) {
                NSFileManager *fileManager = [[NSFileManager alloc] init];
                
                // remove file if it exists
                if ([fileManager fileExistsAtPath:localPath]) {
                    [fileManager removeItemAtPath:localPath error:&error];
                }
                if (!error) {
                    // Move file into place
                    [fileManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:localPath] error:&error];
                }
            }
            
            completion(parsedResult, error);
        } forKey:task];
    }];
    
    [self addTask:task];
    [task resume];
}

#pragma mark - Sharing

+ (void)getSharedLinkForFileAtPath:(NSString *const)path accessToken:(NSString *const)accessToken completion:(void (^const)(NSString *_Nullable urlString))completion
{
    [self getSharedLinkForFileAtPath:path linkType:TJDropboxSharedLinkTypeDefault uploadOrSaveInProgress:NO accessToken:accessToken completion:completion];
}

+ (void)getSharedLinkForFileAtPath:(NSString *const)path linkType:(const TJDropboxSharedLinkType)linkType uploadOrSaveInProgress:(const BOOL)uploadOrSaveInProgress accessToken:(NSString *const)accessToken completion:(void (^const)(NSString *_Nullable urlString))completion
{
    // NOTE: create_shared_link has been deprecated, will likely be removed by Dropbox at some point. https://goo.gl/ZSrxRN
    NSString *const requestPath = linkType == TJDropboxSharedLinkTypeShort ? @"/2/sharing/create_shared_link" : @"/2/sharing/create_shared_link_with_settings";
    NSMutableDictionary *parameters = [NSMutableDictionary new];
    [parameters setObject:[self asciiEncodeString:path] forKey:@"path"];
    if (linkType == TJDropboxSharedLinkTypeShort) {
        [parameters setObject:@YES forKey:@"short_url"];
        if (uploadOrSaveInProgress) {
            [parameters setObject:@"file" forKey:@"pending_upload"];
        }
    } else if (uploadOrSaveInProgress) {
        NSLog(@"[TJDropbox] - Warning in %s: uploadOrSaveInProgress is only compatible with short URL generation. Parameter is being ignored.", __PRETTY_FUNCTION__);
    }
    NSURLRequest *const request = [self apiRequestWithPath:requestPath accessToken:accessToken parameters:parameters];
    [self performAPIRequest:request withCompletion:^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        NSString *urlString = parsedResponse[@"url"];
        if (linkType == TJDropboxSharedLinkTypeDirect && urlString.length > 0) {
            NSURLComponents *const components = [NSURLComponents componentsWithString:urlString];
            components.host = @"dl.dropboxusercontent.com";
            components.queryItems = nil; // the ?dl=0 that Dropbox appends doesn't seem strictly necessary.
            urlString = components.URL.absoluteString;
        }
        completion(urlString);
    }];
}

#pragma mark - Users

+ (void)getSpaceUsageForUserWithAccessToken:(NSString *const)accessToken completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    NSURLRequest *const request = [self apiRequestWithPath:@"/2/users/get_space_usage" accessToken:accessToken parameters:nil];
    [self performAPIRequest:request withCompletion:completion];
}

#pragma mark - Request Management

+ (void)cancelAllRequests
{
    [[self tasksOperationQueue] addOperationWithBlock:^{
        for (NSURLSessionTask *const task in [self _tasks]) {
            [task cancel];
        }
    }];
}

@end

@implementation NSError (TJDropbox)

- (BOOL)tj_isPathNotFoundError
{
    BOOL isPathNotFoundError = NO;
    if ([self.domain isEqualToString:TJDropboxErrorDomain]) {
        NSDictionary *const dropboxErrorDictionary = self.userInfo[TJDropboxErrorUserInfoKeyDropboxError];
        NSString *const tag = dropboxErrorDictionary[@".tag"];
        if ([tag isEqualToString:@"path"]) {
            NSString *const pathTag = dropboxErrorDictionary[@"path"][@".tag"];
            if ([pathTag isEqualToString:@"not_found"]) {
                isPathNotFoundError = YES;
            }
        }
    }
    return isPathNotFoundError;
}

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

@end
