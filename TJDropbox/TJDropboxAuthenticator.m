//
//  TJDropboxAuthenticator.m
//  Close-up
//
//  Created by Tim Johnsen on 3/14/20.
//

#import "TJDropbox.h"
#import "TJDropboxAuthenticator.h"
#import <AuthenticationServices/AuthenticationServices.h>
#if !defined(__IPHONE_12_0) || __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_12_0
#import <SafariServices/SafariServices.h>
#endif

// DO NOT mark as Obj-C direct, will lead to exceptions.
@interface TJDropboxAuthenticatorWebAuthenticationPresentationContextProvider : NSObject

@end

@implementation TJDropboxAuthenticatorWebAuthenticationPresentationContextProvider

#pragma mark - ASWebAuthenticationPresentationContextProviding

+ (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session API_AVAILABLE(ios(13.0))
{
    return [[UIApplication sharedApplication] keyWindow];
}

@end

#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
__attribute__((objc_direct_members))
#endif
@interface TJDropboxAuthenticator ()

@property (nonatomic, copy, class) NSString *tj_clientIdentifier;
@property (nonatomic, copy, class) NSString *tj_codeVerifier;
@property (nonatomic, class) BOOL tj_generateRefreshToken;
@property (nonatomic, copy, class) void (^tj_completion)(NSString *accessToken, NSString *refreshToken, NSDate *expirationDate);

@end

#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
__attribute__((objc_direct_members))
#endif
@implementation TJDropboxAuthenticator

static NSString *_tj_clientIdentifier;
static NSString *_tj_codeVerifier;
static BOOL _tj_generateRefreshToken;
static void (^_tj_completion)(NSString *accessToken, NSString *refreshToken, NSDate *expirationDate);

+ (void)setTj_clientIdentifier:(NSString *)tj_clientIdentifier
{
    _tj_clientIdentifier = tj_clientIdentifier;
}

+ (void)setTj_codeVerifier:(NSString *)tj_codeVerifier
{
    _tj_codeVerifier = tj_codeVerifier;
}

+ (void)setTj_generateRefreshToken:(BOOL)tj_generateRefreshToken
{
    _tj_generateRefreshToken = tj_generateRefreshToken;
}

+ (void)setTj_completion:(void (^)(NSString *, NSString *, NSDate *))tj_completion
{
    _tj_completion = tj_completion;
}

+ (NSString *)tj_clientIdentifier
{
    return _tj_clientIdentifier;
}

+ (NSString *)tj_codeVerifier
{
    return _tj_codeVerifier;
}

+ (BOOL)tj_generateRefreshToken
{
    return _tj_generateRefreshToken;
}

+ (void (^)(NSString *, NSString *, NSDate *))tj_completion
{
    return _tj_completion;
}

+ (void)authenticateWithClientIdentifier:(NSString *const)clientIdentifier
                     bypassingNativeAuth:(const BOOL)bypassNativeAuth
                           bypassingPKCE:(const BOOL)bypassingPKCE
                    generateRefreshToken:(const BOOL)generateRefreshToken
                              completion:(void (^)(NSString *_Nullable accessToken, NSString *_Nullable refreshToken, NSDate *_Nullable expirationDate))completion
{
    NSString *const redirectURLScheme = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier].scheme;
    if (![[[[NSBundle mainBundle] infoDictionary] valueForKeyPath:@"CFBundleURLTypes.CFBundleURLSchemes.@unionOfArrays.self"] containsObject:redirectURLScheme]) { // https://forums.developer.apple.com/thread/31307
        NSAssert(NO, @"You must add the \"%@\" scheme to your info.plist's \"CFBundleURLTypes\"", redirectURLScheme);
        completion(nil, nil, nil);
        return;
    }
    
    NSString *const codeVerifier = bypassingPKCE ? nil : [NSString stringWithFormat:@"%@-%@", [[NSUUID UUID] UUIDString], [[NSUUID UUID] UUIDString]];
    if (bypassNativeAuth) {
        [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                             codeVerifier:codeVerifier
                                     generateRefreshToken:generateRefreshToken
                                               completion:completion];
    } else {
        NSURL *const tokenAuthURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier
                                                                                  codeVerifier:codeVerifier
                                                                          generateRefreshToken:generateRefreshToken];
        [[UIApplication sharedApplication] openURL:tokenAuthURL
                                           options:@{}
                                 completionHandler:^(BOOL success) {
            if (success) {
                [self setTj_clientIdentifier:clientIdentifier];
                [self setTj_codeVerifier:codeVerifier];
                [self setTj_generateRefreshToken:generateRefreshToken];
                [self setTj_completion:completion];
            } else {
                [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                                     codeVerifier:codeVerifier
                                             generateRefreshToken:generateRefreshToken
                                                       completion:completion];
            }
        }];
    }
}

+ (void)authenticateUsingSafariWithClientIdentifier:(NSString *const)clientIdentifier
                                       codeVerifier:(NSString *const)codeVerifier
                               generateRefreshToken:(const BOOL)generateRefreshToken
                                         completion:(void (^)(NSString *, NSString *, NSDate *))completion
{
    NSURL *const url = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier
                                                                 redirectURL:nil
                                                                codeVerifier:codeVerifier
                                                        generateRefreshToken:generateRefreshToken];
    NSString *const redirectURLScheme = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier].scheme;
    
    // Reference needs to be held as long as this is in progress, otherwise the UI disappears.
    static id session;
    void (^completionHandler)(NSURL *, NSError *) = ^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        // Process results.
        [self tryHandleAuthenticationCallbackWithURL:callbackURL
                                    clientIdentifier:clientIdentifier
                                        codeVerifier:codeVerifier
                                generateRefreshToken:generateRefreshToken
                                          completion:completion];
        // Break reference so session is deallocated.
        session = nil;
    };
    if (@available(iOS 12.0, *)) {
        session = [[ASWebAuthenticationSession alloc] initWithURL:url
                                                callbackURLScheme:redirectURLScheme
                                                completionHandler:completionHandler];
        if (@available(iOS 13.0, *)) {
            [(ASWebAuthenticationSession *)session setPresentationContextProvider:(id<ASWebAuthenticationPresentationContextProviding>)[TJDropboxAuthenticatorWebAuthenticationPresentationContextProvider class]];
        }
        [(ASWebAuthenticationSession *)session start];
#if !defined(__IPHONE_12_0) || __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_12_0
    } else if (@available(iOS 11.0, *)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        session = [[SFAuthenticationSession alloc] initWithURL:url
                                             callbackURLScheme:redirectURLScheme
                                             completionHandler:completionHandler];
        [(SFAuthenticationSession *)session start];
#pragma clang diagnostic pop
#endif
    } else {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (success) {
                [self setTj_clientIdentifier:clientIdentifier];
                [self setTj_codeVerifier:codeVerifier];
                [self setTj_generateRefreshToken:generateRefreshToken];
                [self setTj_completion:completion];
            } else {
                completion(nil, nil, nil);
            }
        }];
    }
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
{
    return [self tryHandleAuthenticationCallbackWithURL:url
                                       clientIdentifier:[self tj_clientIdentifier]
                                           codeVerifier:[self tj_codeVerifier]
                                   generateRefreshToken:[self tj_generateRefreshToken]
                                             completion:[self tj_completion]];
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
                              clientIdentifier:(NSString *const)clientIdentifier
                                  codeVerifier:(NSString *const)codeVerifier
                          generateRefreshToken:(const BOOL)generateRefreshToken
                                    completion:(void (^)(NSString *accessToken, NSString *refreshToken, NSDate *_Nullable expirationDate))completion
{
    BOOL handledURL = NO;
    NSURL *const redirectURL = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier];
    NSString *const redirectURLScheme = redirectURL.scheme;
    if (url && redirectURLScheme && [url.absoluteString hasPrefix:redirectURLScheme]) {
        NSURLComponents *const components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
        NSString *code = nil;
        BOOL codeIsAccessToken = NO;
        for (NSURLQueryItem *const queryItem in components.queryItems) {
            if ([queryItem.name isEqualToString:@"code"]) {
                code = queryItem.value;
                break;
            } else if ([queryItem.name isEqualToString:@"state"] && [queryItem.value containsString:@"oauth2code"]) {
                codeIsAccessToken = YES;
                break;
            }
        }
        NSString *token = nil;
        NSString *refreshToken = nil;
        NSDate *expirationDate = nil;
        [TJDropbox accessToken:&token refreshToken:&refreshToken expirationDate:&expirationDate fromDropboxAppAuthenticationURL:url];
        if (!token) {
            [TJDropbox accessToken:&token refreshToken:&refreshToken expirationDate:&expirationDate fromURL:url withClientIdentifier:clientIdentifier];
        }
        if (codeIsAccessToken) {
            code = token;
        }
        if (code) {
            if (codeVerifier) {
                // Initiating requests while the app is entering the foreground often leads to failures since we're not using background tasks.
                // Let's wait until we're definitely active to perform our auth request.
                if ([[UIApplication sharedApplication] applicationState] != UIApplicationStateActive) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self tryHandleAuthenticationCallbackWithURL:url
                                                    clientIdentifier:clientIdentifier
                                                        codeVerifier:codeVerifier
                                                generateRefreshToken:generateRefreshToken
                                                          completion:completion];
                    });
                } else {
                    [TJDropbox accessTokenFromCode:code
                              withClientIdentifier:clientIdentifier
                                      codeVerifier:codeVerifier
                              generateRefreshToken:generateRefreshToken
                                       redirectURL:redirectURL
                                        completion:^(NSString * _Nullable accessToken, NSString * _Nullable refreshToken, NSDate *_Nullable expirationDate, NSError * _Nullable error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(accessToken, refreshToken, expirationDate);
                        });
                    }];
                }
            } else {
                completion(nil, nil, nil);
            }
        } else {
            completion(token, refreshToken, expirationDate);
        }
        
        [self setTj_clientIdentifier:nil];
        [self setTj_codeVerifier:nil];
        [self setTj_generateRefreshToken:NO];
        [self setTj_completion:nil];
        
        handledURL = YES;
    }
    return handledURL;
}

@end
