//
//  TJDropbox.m
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import "TJDropbox.h"
#import <CommonCrypto/CommonDigest.h>
#import <os/lock.h>
#import <zlib.h>

NSString *const TJDropboxErrorDomain = @"TJDropboxErrorDomain";
NSString *const TJDropboxErrorUserInfoKeyResponse = @"response";
NSString *const TJDropboxErrorUserInfoKeyDropboxError = @"dropboxError";
NSString *const TJDropboxErrorUserInfoKeyErrorString = @"errorString";

NSNotificationName const TJDropboxCredentialDidRefreshAccessTokenNotification = @"TJDropboxCredentialDidRefreshAccessTokenNotification";

#if defined(__has_attribute) && __has_attribute(objc_direct_members)
__attribute__((objc_direct_members))
#endif
@interface TJDropboxCredential () {
    os_unfair_lock _lock;
}

@property (nonatomic, copy, readwrite) NSString *accessToken;

@property (nonatomic, copy, readwrite) NSString *refreshToken;
@property (nonatomic, readwrite) NSDate *expirationDate;
@property (nonatomic, copy, readwrite) NSString *clientIdentifier;

@property (nonatomic) NSMutableArray<void (^)(NSDictionary *, NSError *)> *refreshCompletionBlocks;

@end

@implementation TJDropboxCredential

- (instancetype)initWithAccessToken:(NSString *const)accessToken
{
    if (self = [super init]) {
        self.accessToken = accessToken;
        _lock = OS_UNFAIR_LOCK_INIT;
    }
    return self;
}

- (instancetype)initWithAccessToken:(NSString *const)accessToken
                       refreshToken:(NSString *const)refreshToken
                     expirationDate:(NSDate *const)expirationDate
                   clientIdentifier:(NSString *const)clientIdentifier
{
    if (self = [self initWithAccessToken:accessToken]) {
        if (refreshToken && expirationDate && clientIdentifier) {
            self.refreshToken = refreshToken;
            self.expirationDate = expirationDate;
            self.clientIdentifier = clientIdentifier;
        }
    }
    return self;
}

/// Similar to the public initializer but params are nullable
- (instancetype)initPrivateWithAccessToken:(NSString *const)accessToken
                              refreshToken:(NSString *const)refreshToken
                            expirationDate:(NSDate *const)expirationDate
                          clientIdentifier:(NSString *const)clientIdentifier
{
    if (accessToken) {
        if (refreshToken && expirationDate && clientIdentifier) {
            return [self initWithAccessToken:accessToken
                                refreshToken:refreshToken
                              expirationDate:expirationDate
                            clientIdentifier:clientIdentifier];
        } else {
            return [self initWithAccessToken:accessToken];
        }
    }
    return nil;
}

- (instancetype)initWithSerializedStringValue:(NSString *)serializedStringValue
                             clientIdentifier:(nonnull NSString *)clientIdentifier
{
    NSArray<NSString *> *const serializedStringValueComponents = [serializedStringValue componentsSeparatedByString:@"\n"];
    NSString *const accessToken = serializedStringValueComponents[0];
    NSString *refreshToken = nil;
    NSDate *expirationDate = nil;
    if (serializedStringValueComponents.count == 3) {
        refreshToken = serializedStringValueComponents[1];
        expirationDate = [NSDate dateWithTimeIntervalSinceReferenceDate:[serializedStringValueComponents[2] doubleValue]];
    }
    return [self initPrivateWithAccessToken:accessToken
                               refreshToken:refreshToken
                             expirationDate:expirationDate
                           clientIdentifier:clientIdentifier];
}

- (NSString *)serializedStringValue
{
    __block NSString *serializedStringValue;
    [self performSynchronized:^{
        serializedStringValue = self.accessToken;
        if (self.refreshToken && self.expirationDate) {
            serializedStringValue = [serializedStringValue stringByAppendingFormat:@"\n%@\n%@", self.refreshToken, @([self.expirationDate timeIntervalSinceReferenceDate])];
        }
    }];
    return serializedStringValue;
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[TJDropboxCredential class]]) {
        // Two credentials are considered equal if:
        // 1. They have the same refresh token
        // 2. They have no refresh tokens but the same access token
        return [[(TJDropboxCredential *)object refreshToken] isEqual:self.refreshToken] ||
        ([(TJDropboxCredential *)object refreshToken] == nil &&
         self.refreshToken == nil &&
         [[(TJDropboxCredential *)object accessToken] isEqual:self.accessToken]);
    }
    return NO;
}

- (void)performSynchronized:(dispatch_block_t)block {
    os_unfair_lock_lock(&_lock);
    block();
    os_unfair_lock_unlock(&_lock);
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
    if (@available(iOS 14.5, macOS 11.3, *)) {
        if (!progressBlock) {
            task.prefersIncrementalDelivery = NO;
        }
    }
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

// Copied from https://tijo.link/k2OViy
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
                                 generateRefreshToken:(const BOOL)generateRefreshToken
{
    // https://www.dropbox.com/developers/documentation/http/documentation#auth
    
    if (!redirectURL) {
        redirectURL = [self defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier];
    }
    NSString *const codeChallenge = codeVerifier ? _codeChallengeFromCodeVerifier(codeVerifier) : nil;
    
    NSURLComponents *const components = [NSURLComponents componentsWithURL:[NSURL URLWithString:@"https://www.dropbox.com/oauth2/authorize"] resolvingAgainstBaseURL:NO];
    NSMutableArray<NSURLQueryItem *> *const queryItems = [NSMutableArray arrayWithObjects:
                                                          [NSURLQueryItem queryItemWithName:@"client_id" value:clientIdentifier],
                                                          [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectURL.absoluteString],
                                                          [NSURLQueryItem queryItemWithName:@"response_type" value:codeChallenge ? @"code" : @"token"],
                                                          [NSURLQueryItem queryItemWithName:@"disable_signup" value:@"true"],
                                                          // Following params only apply if verifier is supplied
                                                          codeChallenge ? [NSURLQueryItem queryItemWithName:@"code_challenge" value:codeChallenge] : nil,
                                                          [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
                                                          nil
                                                          ];
    if (generateRefreshToken) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"token_access_type" value:@"offline"]]; // https://dropbox.tech/developers/migrating-app-permissions-and-access-tokens#updating-access-token-type
    }
    components.queryItems = queryItems;
    return components.URL;
}

+ (NSURL *)defaultTokenAuthenticationRedirectURLWithClientIdentifier:(NSString *const)clientIdentifier
{
    return [NSURL URLWithString:[NSString stringWithFormat:@"db-%@://2/token", clientIdentifier]];
}

+ (nullable TJDropboxCredential *)credentialFromURL:(NSURL *const)url withRedirectURL:(NSURL *const)redirectURL
{
    TJDropboxCredential *credential = nil;
    if ([url.absoluteString hasPrefix:redirectURL.absoluteString]) {
        NSString *const fragment = url.fragment;
        NSURLComponents *const components = [NSURLComponents new];
        components.query = fragment;
        for (NSURLQueryItem *const item in components.queryItems) {
            if ([item.name isEqualToString:@"access_token"]) {
                credential = [[TJDropboxCredential alloc] initWithAccessToken:item.value];
                break;
            }
        }
    }
    return credential;
}

+ (nullable TJDropboxCredential *)credentialFromURL:(NSURL *const)url withClientIdentifier:(NSString *const)clientIdentifier
{
    return [self credentialFromURL:url withRedirectURL:[self defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier]];
}

+ (void)credentialFromCode:(NSString *const)code
      withClientIdentifier:(NSString *const)clientIdentifier
              codeVerifier:(NSString *const)codeVerifier
               redirectURL:(NSURL *const)redirectURL
                completion:(void (^const)(TJDropboxCredential *_Nullable, NSError *_Nullable))completion
{
    // https://www.dropbox.com/developers/documentation/http/documentation#oauth2-token
    // https://tijo.link/BmeoVo
    
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
        NSString *const accessToken = parsedResponse[@"access_token"];
        NSString *const refreshToken = parsedResponse[@"refresh_token"];
        const id expiresInValue = parsedResponse[@"expires_in"];
        NSDate *const expirationDate = expiresInValue != nil ? [NSDate dateWithTimeIntervalSinceNow:[expiresInValue doubleValue]] : nil;
        completion([[TJDropboxCredential alloc] initPrivateWithAccessToken:accessToken
                                                              refreshToken:refreshToken
                                                            expirationDate:expirationDate
                                                          clientIdentifier:clientIdentifier],
                   error);
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
                                      generateRefreshToken:(const BOOL)generateRefreshToken
{
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L288-L303
    // https://github.com/dropbox/SwiftyDropbox/blob/master/Source/OAuth.swift#L274-L282
    
    NSURLComponents *const components = [NSURLComponents componentsWithString:@"dbapi-2://1/connect"];
    
    NSString *stateString;
    NSString *extraQueryParams = nil;
    if (codeVerifier) {
        NSString *const codeChallenge = _codeChallengeFromCodeVerifier(codeVerifier);
        stateString = [NSString stringWithFormat:@"oauth2code:%@:S256:", codeChallenge];
        
        if (generateRefreshToken) {
            stateString = [stateString stringByAppendingString:@"offline"];
        }
        
        NSURLComponents *const extraComponents = [NSURLComponents new];
        
        extraComponents.queryItems = [NSArray arrayWithObjects:
                                      [NSURLQueryItem queryItemWithName:@"code_challenge" value:codeChallenge],
                                      [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
                                      [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
                                      generateRefreshToken ? [NSURLQueryItem queryItemWithName:@"token_access_type" value:@"offline"] : nil,
                                      nil
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
                             // Following params only apply if verifier is supplied https://tijo.link/QObA8d
                             extraQueryParams != nil ? [NSURLQueryItem queryItemWithName:@"extra_query_params" value:extraQueryParams] : nil,
                             nil
                             ];
    return components.URL;
}

+ (nullable TJDropboxCredential *)credentialFromDropboxAppAuthenticationURL:(NSURL *const)url
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
            // Note: It seems that you cannot get refresh tokens from app-to-app auth.
        }
    }
    return accessToken != nil ? [[TJDropboxCredential alloc] initWithAccessToken:accessToken] : nil;
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
    NSMutableString *const result = string != nil ? [NSMutableString stringWithCapacity:stringLength] : nil;
    
    for (NSUInteger i = 0; i < stringLength; i++) {
        const unichar character = [string characterAtIndex:i];
        if (character > 127) {
            [result appendFormat:@"\\u%04x", character];
        } else {
            [result appendFormat:@"%c", character];
        }
    }
    
    return result;
}

static NSString * _parameterStringForParameters(NSDictionary<NSString *, id> *parameters)
{
    NSString *parameterString = nil;
    if (parameters.count > 0) {
        NSError *error = nil;
        NSJSONWritingOptions options = 0;
        if (@available(iOS 13.0, macOS 10.15, *)) {
            options = NSJSONWritingWithoutEscapingSlashes;
        }
        NSData *const parameterData = [NSJSONSerialization dataWithJSONObject:parameters options:options error:&error];
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
    
    return request;
}

// Thanks Claude https://tijo.link/BGdVNx
static NSData *_gzipCompressData(NSData *const data, NSError **error) {
   if (!data.length) {
       if (error) {
           *error = [NSError errorWithDomain:@"CompressionErrorDomain" code:1
               userInfo:@{NSLocalizedDescriptionKey: @"Invalid input data"}];
       }
       return nil;
   }
   
   z_stream strm;
   strm.zalloc = Z_NULL;
   strm.zfree = Z_NULL;
   strm.opaque = Z_NULL;
   
   // Initialize deflate with gzip format
   if (deflateInit2(&strm, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
       if (error) {
           *error = [NSError errorWithDomain:@"CompressionErrorDomain" code:2
               userInfo:@{NSLocalizedDescriptionKey: @"Failed to initialize compression"}];
       }
       return nil;
   }
   
   // Set up input
   strm.avail_in = (uInt)data.length;
   strm.next_in = (Bytef *)data.bytes;
   
   // Prepare output buffer (compress can increase size)
   NSMutableData *compressedData = [NSMutableData dataWithLength:data.length * 1.1 + 12];
   strm.avail_out = (uInt)compressedData.length;
   strm.next_out = compressedData.mutableBytes;
   
   // Compress
   if (deflate(&strm, Z_FINISH) != Z_STREAM_END) {
       deflateEnd(&strm);
       if (error) {
           *error = [NSError errorWithDomain:@"CompressionErrorDomain" code:3
               userInfo:@{NSLocalizedDescriptionKey: @"Compression failed"}];
       }
       return nil;
   }
   
   // Cleanup and finalize
   [compressedData setLength:strm.total_out];
   deflateEnd(&strm);
   
   return compressedData;
}

static NSMutableURLRequest *_apiRequest(NSString *const path, NSString *const accessToken, NSDictionary<NSString *, id> *const parameters)
{
    NSMutableURLRequest *const request = _baseRequest(@"https://api.dropboxapi.com", path, accessToken);
    request.HTTPBody = [_parameterStringForParameters(parameters) dataUsingEncoding:NSUTF8StringEncoding];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    
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

static TJDropboxURLSessionTaskDelegate *_taskDelegate(void)
{
    static TJDropboxURLSessionTaskDelegate *taskDelegate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        taskDelegate = [TJDropboxURLSessionTaskDelegate new];
    });
    return taskDelegate;
}

static NSURLSession *_session(void)
{
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        TJDropboxURLSessionTaskDelegate *taskDelegate = _taskDelegate();
        NSURLSessionConfiguration *const configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.shouldUseExtendedBackgroundIdleMode = YES; // Allows requests to run better when the app is backgrounded https://twitter.com/BigZaphod/status/1164977540479553543
        configuration.waitsForConnectivity = YES;
        configuration.timeoutIntervalForResource = 60;
        session = [NSURLSession sessionWithConfiguration:configuration delegate:taskDelegate delegateQueue:taskDelegate.serialOperationQueue];
    });
    return session;
}

static void _addTask(TJDropboxCredential *credential,
                     NSURLSessionTask *(^taskBlock)(void),
                     void (^const refreshErrorCompletion)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))
{
    dispatch_block_t performTaskBlock = ^{
        NSURLSessionTask *task = taskBlock();
        [task resume];
    };
    __block BOOL runBlock;
    if (credential) {
        [credential performSynchronized:^{
            if (credential.expirationDate != nil && credential.expirationDate.timeIntervalSinceNow < 600.0) { // Refresh if there are fewer than 10 minutes until expiration
                void (^refreshCompletionBlock)(NSDictionary *, NSError *) = ^(NSDictionary *parsedResponse, NSError *error) {
                    if (error) {
                        refreshErrorCompletion(parsedResponse, error);
                    } else {
                        performTaskBlock();
                    }
                };
                if (credential.refreshCompletionBlocks) {
                    [credential.refreshCompletionBlocks addObject:refreshErrorCompletion];
                } else {
                    credential.refreshCompletionBlocks = [NSMutableArray arrayWithObject:refreshCompletionBlock];
                    _refreshCredential(credential, ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
                        for (void (^block)(NSDictionary *, NSError *) in credential.refreshCompletionBlocks) {
                            block(parsedResponse, error);
                        }
                        credential.refreshCompletionBlocks = nil;
                    });
                }
                runBlock = NO;
            } else {
                runBlock = YES;
            }
        }];
    } else {
        runBlock = YES;
    }
    
    if (runBlock) {
        performTaskBlock();
    }
}

static void _performAPIRequest(TJDropboxCredential *credential, NSURLRequest *(^requestBlock)(void), void (^const completion)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))
{
    _addTask(credential,
             ^NSURLSessionTask *{
        return [_session() dataTaskWithRequest:requestBlock() completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            _processResult(data, response, &error, &parsedResult);
            completion(parsedResult, error);
        }];
    },
             completion);
}

static void _refreshCredential(TJDropboxCredential *const credential, void (^completion)(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error))
{
    _performAPIRequest(nil,
                       ^NSURLRequest *{
        // https://www.dropbox.com/developers/documentation/http/documentation#oauth2-token
        // https://tijo.link/BmeoVo
        NSMutableURLRequest *const request = _apiRequest(@"/oauth2/token", nil, nil);
        NSURLComponents *const components = [NSURLComponents new];
        components.queryItems = @[
            [NSURLQueryItem queryItemWithName:@"grant_type" value:@"refresh_token"],
            [NSURLQueryItem queryItemWithName:@"refresh_token" value:credential.refreshToken],
            [NSURLQueryItem queryItemWithName:@"client_id" value:credential.clientIdentifier],
        ];
        request.HTTPBody = [components.query dataUsingEncoding:NSUTF8StringEncoding];
        [request addValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
        return request;
    },
                       ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        
        NSString *const accessToken = parsedResponse[@"access_token"];
        const id expiresInValue = parsedResponse[@"expires_in"];
        NSDate *const expirationDate = expiresInValue != nil ? [NSDate dateWithTimeIntervalSinceNow:[expiresInValue doubleValue]] : nil;
        if (accessToken && expirationDate) {
            [credential performSynchronized:^{
                credential.accessToken = accessToken;
                credential.expirationDate = expirationDate;
            }];
            [[NSNotificationCenter defaultCenter] postNotificationName:TJDropboxCredentialDidRefreshAccessTokenNotification
                                                                object:credential];
        }
        completion(parsedResponse, error);
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
        [parameters setObject:@NO forKey:@"include_non_downloadable_files"];
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

+ (void)listFolderWithPath:(NSString *const)path credential:(TJDropboxCredential *const)credential cursor:(NSString *const)inCursor includeDeleted:(const BOOL)includeDeleted accumulatedFiles:(NSArray *const)accumulatedFiles completion:(void (^const)(NSArray<NSDictionary *> *_Nullable entries, NSString *_Nullable cursor, NSError *_Nullable error))completion
{
    _performAPIRequest(credential,
                       ^NSURLRequest *{
        return _listFolderRequest(path, credential.accessToken, inCursor, includeDeleted);
    },
                       ^(NSDictionary * _Nullable parsedResponse, NSError * _Nullable error) {
        NSArray *const files = [parsedResponse objectForKey:@"entries"];
        id hasMoreObject = [parsedResponse objectForKey:@"has_more"];
        if (!error && files != nil && [hasMoreObject isKindOfClass:[NSNumber class]]) {
            NSArray *const files = [parsedResponse objectForKey:@"entries"];
            NSArray *newlyAccumulatedFiles;
            
            if ([files isKindOfClass:[NSArray class]]) {
                newlyAccumulatedFiles = accumulatedFiles.count > 0 ? [accumulatedFiles arrayByAddingObjectsFromArray:files] : files;
            } else {
                newlyAccumulatedFiles = nil;
                completion(nil, nil, error != nil ? error : [NSError errorWithDomain:TJDropboxErrorDomain code:3 userInfo:nil]);
                return;
            }
            
            const BOOL hasMore = [(NSNumber *)hasMoreObject boolValue];
            const id outCursorObject = [parsedResponse objectForKey:@"cursor"];
            NSString *const outCursor = [outCursorObject isKindOfClass:[NSString class]] ? outCursorObject : nil;
            if (hasMore) {
                if (outCursor) {
                    // Fetch next page
                    [self listFolderWithPath:path credential:credential cursor:outCursor includeDeleted:includeDeleted accumulatedFiles:newlyAccumulatedFiles completion:completion];
                } else {
                    // We can't load more without a cursor
                    completion(nil, nil, error != nil ? error : [NSError errorWithDomain:TJDropboxErrorDomain code:1 userInfo:nil]);
                }
            } else {
                // All files fetched, finish.
                completion(newlyAccumulatedFiles, outCursor, error);
            }
        } else {
            completion(nil, nil, error != nil ? error : [NSError errorWithDomain:TJDropboxErrorDomain code:2 userInfo:nil]);
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
    _addTask(credential,
             ^NSURLSessionTask *{
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
    },
             completion);
}

+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self uploadFileAtPath:localPath toPath:remotePath overwriteExisting:NO muteDesktopNotifications:NO credential:credential progressBlock:nil completion:completion];
}

+ (void)uploadFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting muteDesktopNotifications:(const BOOL)muteDesktopNotifications credential:(TJDropboxCredential *const)credential progressBlock:(void (^_Nullable const)(CGFloat progress))progressBlock completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    _addTask(credential,
             ^NSURLSessionTask *{
        NSMutableDictionary<NSString *, id> *const parameters = [NSMutableDictionary new];
        parameters[@"path"] = _asciiEncodeString(remotePath);
        if (overwriteExisting) {
            parameters[@"mode"] = @{@".tag": @"overwrite"};
        }
        if (muteDesktopNotifications) {
            parameters[@"mute"] = @YES;
        }
        NSMutableURLRequest *const request = _contentRequest(@"/2/files/upload", credential.accessToken, parameters);
        
        NSData *const data = [NSData dataWithContentsOfFile:localPath];
        NSError *error;
        NSData *const compressedData = _gzipCompressData(data, &error); // TODO: We should probably limit this based on file size & RAM
        
        NSURLSessionUploadTask *task;
        if (error == nil && compressedData.length > 0 && compressedData.length < data.length) {
            [request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"];
            [request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
            task = [_session() uploadTaskWithRequest:request fromData:compressedData];
        } else {
            task = [_session() uploadTaskWithRequest:request fromFile:[NSURL fileURLWithPath:localPath isDirectory:NO]];
        }
        
        task.priority = NSURLSessionTaskPriorityHigh;
        
        if (@available(iOS 14.5, macOS 11.3, *)) {
            if (!progressBlock) {
                task.prefersIncrementalDelivery = NO;
            }
        }
            
        [_taskDelegate() setProgressBlock:progressBlock
                          completionBlock:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
            NSDictionary *parsedResult = nil;
            _processResult(data, response, &error, &parsedResult);
            
            completion(parsedResult, error);
        }
                              forDataTask:task];
        return task;
    },
             completion);
}

+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath credential:(TJDropboxCredential *const)credential completion:(void (^const)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))completion
{
    [self uploadLargeFileAtPath:localPath toPath:remotePath overwriteExisting:NO muteDesktopNotifications:NO credential:credential progressBlock:nil completion:completion];
}

+ (void)uploadLargeFileAtPath:(NSString *const)localPath toPath:(NSString *const)remotePath overwriteExisting:(const BOOL)overwriteExisting muteDesktopNotifications:(const BOOL)muteDesktopNotifications credential:(TJDropboxCredential *const)credential progressBlock:(void (^const _Nullable)(CGFloat))progressBlock completion:(nonnull void (^const)(NSDictionary * _Nullable, NSError * _Nullable))completion
{
    _addTask(credential,
             ^NSURLSessionTask *{
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
    },
             completion);
}

static void _uploadChunk(NSFileHandle *const fileHandle, unsigned long long fileSize, NSString *const sessionIdentifier, NSString *const remotePath, const BOOL overwriteExisting, const BOOL muteDesktopNotifications, TJDropboxCredential *credential, void (^progressBlock)(CGFloat progress), void (^completion)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))
{
    _addTask(credential,
             ^NSURLSessionTask *{
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
        
        if (@available(iOS 14.5, macOS 11.3, *)) {
            if (!totalProgressBlock) {
                task.prefersIncrementalDelivery = NO;
            }
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
    },
             completion);
}

static void _finishLargeUpload(NSFileHandle *const fileHandle, NSString *const sessionIdentifier, NSString *const remotePath, const BOOL overwriteExisting, const BOOL muteDesktopNotifications, TJDropboxCredential *const credential, void (^completion)(NSDictionary *_Nullable parsedResponse, NSError *_Nullable error))
{
    _addTask(credential,
             ^NSURLSessionTask *{
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
    },
             completion);
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
    _addTask(credential,
             ^NSURLSessionTask *{
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
    },
             completion);
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
        // NOTE: create_shared_link has been deprecated, will likely be removed by Dropbox at some point. https://tijo.link/mluVlJ
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
                components.host = [components.host stringByReplacingOccurrencesOfString:@"www." withString:@""];
            }
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
    [_session() getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> * _Nonnull tasks) {
        [tasks makeObjectsPerformSelector:@selector(cancel)];
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
