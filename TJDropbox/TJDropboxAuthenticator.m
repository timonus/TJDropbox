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

#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
__attribute__((objc_direct_members))
#endif
@interface TJDropboxAuthenticationOptions ()

@property (nonatomic, readonly) BOOL generateRefreshToken;
@property (nonatomic, readonly) BOOL bypassNativeAuth;
@property (nonatomic, readonly) BOOL bypassPKCE;

@end

#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
__attribute__((objc_direct_members))
#endif
@implementation TJDropboxAuthenticationOptions

- (instancetype)initWithGenerateRefreshToken:(BOOL)generateRefreshToken
                            bypassNativeAuth:(const BOOL)bypassNativeAuth {
    if (self = [super init]) {
        _generateRefreshToken = generateRefreshToken;
        _bypassNativeAuth = bypassNativeAuth;
    }
    return self;
}

- (instancetype)initWithBypassNativeAuth:(const BOOL)bypassNativeAuth
                              bypassPKCE:(const BOOL)bypassPKCE
{
    if (self = [super init]) {
        _bypassNativeAuth = bypassNativeAuth;
        _bypassPKCE = bypassPKCE;
    }
    return self;
}

@end

// DO NOT mark as Obj-C direct, will lead to exceptions.
@interface TJDropboxAuthenticatorWebAuthenticationPresentationContextProvider : NSObject

@end

@implementation TJDropboxAuthenticatorWebAuthenticationPresentationContextProvider

#pragma mark - ASWebAuthenticationPresentationContextProviding

+ (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session API_AVAILABLE(ios(13.0))
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [[UIApplication sharedApplication] keyWindow];
#pragma clang diagnostic pop
}

@end

#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
__attribute__((objc_direct_members))
#endif
@implementation TJDropboxAuthenticator

static NSString *_tj_clientIdentifier;
static NSString *_tj_codeVerifier;
static void (^_tj_completion)(TJDropboxCredential *);

+ (void)authenticateWithClientIdentifier:(NSString *const)clientIdentifier
                                 options:(nullable TJDropboxAuthenticationOptions *)options
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
             presentationContextProvider:(id<ASWebAuthenticationPresentationContextProviding>)presentationContextProvider
#pragma clang diagnostic pop
                              completion:(void (^)(TJDropboxCredential *_Nullable))completion
{
    NSString *const redirectURLScheme = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier].scheme;
    if (![[[[NSBundle mainBundle] infoDictionary] valueForKeyPath:@"CFBundleURLTypes.CFBundleURLSchemes.@unionOfArrays.self"] containsObject:redirectURLScheme]) { // https://forums.developer.apple.com/thread/31307
        NSAssert(NO, @"You must add the \"%@\" scheme to your info.plist's \"CFBundleURLTypes\"", redirectURLScheme);
        completion(nil);
        return;
    }
    
    NSString *const codeVerifier = options.bypassPKCE ? nil : [NSString stringWithFormat:@"%@-%@", [[NSUUID UUID] UUIDString], [[NSUUID UUID] UUIDString]];
    if (options.bypassNativeAuth) {
        [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                             codeVerifier:codeVerifier
                                     generateRefreshToken:options.generateRefreshToken
                              presentationContextProvider:presentationContextProvider
                                               completion:completion];
    } else {
        NSURL *const tokenAuthURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier
                                                                                  codeVerifier:codeVerifier
                                                                          generateRefreshToken:options.generateRefreshToken];
        [[UIApplication sharedApplication] openURL:tokenAuthURL
                                           options:@{}
                                 completionHandler:^(BOOL success) {
            if (success) {
                _tj_clientIdentifier = clientIdentifier;
                _tj_codeVerifier = codeVerifier;
                _tj_completion = completion;
            } else {
                [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                                     codeVerifier:codeVerifier
                                             generateRefreshToken:options.generateRefreshToken
                                      presentationContextProvider:presentationContextProvider
                                                       completion:completion];
            }
        }];
    }
}

+ (void)authenticateUsingSafariWithClientIdentifier:(NSString *const)clientIdentifier
                                       codeVerifier:(NSString *const)codeVerifier
                               generateRefreshToken:(const BOOL)generateRefreshToken
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
                        presentationContextProvider:(id<ASWebAuthenticationPresentationContextProviding>)presentationContextProvider
#pragma clang diagnostic pop
                                         completion:(void (^)(TJDropboxCredential *))completion
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
                                          completion:completion];
        // Break reference so session is deallocated.
        session = nil;
    };
    if (@available(iOS 12.0, *)) {
        session = [[ASWebAuthenticationSession alloc] initWithURL:url
                                                callbackURLScheme:redirectURLScheme
                                                completionHandler:completionHandler];
        if (@available(iOS 13.0, *)) {
            [(ASWebAuthenticationSession *)session setPresentationContextProvider:presentationContextProvider ?: (id<ASWebAuthenticationPresentationContextProviding>)[TJDropboxAuthenticatorWebAuthenticationPresentationContextProvider class]];
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
                _tj_clientIdentifier = clientIdentifier;
                _tj_codeVerifier = codeVerifier;
                _tj_completion = completion;
            } else {
                completion(nil);
            }
        }];
    }
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
{
    return [self tryHandleAuthenticationCallbackWithURL:url
                                       clientIdentifier:_tj_clientIdentifier
                                           codeVerifier:_tj_codeVerifier
                                             completion:_tj_completion];
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
                              clientIdentifier:(NSString *const)clientIdentifier
                                  codeVerifier:(NSString *const)codeVerifier
                                    completion:(void (^)(TJDropboxCredential *))completion
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
        TJDropboxCredential *const credential = [TJDropbox credentialFromDropboxAppAuthenticationURL:url] ?: [TJDropbox credentialFromURL:url withClientIdentifier:clientIdentifier];
        if (codeIsAccessToken) {
            code = credential.accessToken;
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
                                                          completion:completion];
                    });
                } else {
                    [TJDropbox credentialFromCode:code
                             withClientIdentifier:clientIdentifier
                                     codeVerifier:codeVerifier
                                      redirectURL:redirectURL
                                       completion:^(TJDropboxCredential *credential, NSError * _Nullable error) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(credential);
                        });
                    }];
                }
            } else {
                completion(nil);
            }
        } else {
            completion(credential);
        }
        
        _tj_clientIdentifier = nil;
        _tj_codeVerifier = nil;
        _tj_completion = nil;
        
        handledURL = YES;
    }
    return handledURL;
}

@end
