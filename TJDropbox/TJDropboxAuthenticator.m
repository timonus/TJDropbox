//
//  TJDropboxAuthenticator.m
//  Close-up
//
//  Created by Tim Johnsen on 3/14/20.
//

#import "TJDropbox.h"
#import "TJDropboxAuthenticator.h"
#import <SafariServices/SafariServices.h>
#import <AuthenticationServices/AuthenticationServices.h>

#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
__attribute__((objc_direct_members))
#endif
@interface TJDropboxAuthenticator ()

@property (nonatomic, copy, class) NSString *tj_clientIdentifier;
@property (nonatomic, copy, class) NSString *tj_codeVerifier;
@property (nonatomic, copy, class) void (^tj_completion)(NSString *accessToken);

@end

#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
__attribute__((objc_direct_members))
#endif
@implementation TJDropboxAuthenticator

static NSString *_tj_clientIdentifier;
static NSString *_tj_codeVerifier;
static void (^_tj_completion)(NSString *accessToken);

+ (void)setTj_clientIdentifier:(NSString *)tj_clientIdentifier
{
    _tj_clientIdentifier = tj_clientIdentifier;
}

+ (void)setTj_codeVerifier:(NSString *)tj_codeVerifier
{
    _tj_codeVerifier = tj_codeVerifier;
}

+ (void)setTj_completion:(void (^)(NSString *))tj_completion
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

+ (void (^)(NSString *))tj_completion
{
    return _tj_completion;
}

+ (void)authenticateWithClientIdentifier:(NSString *const)clientIdentifier
                     bypassingNativeAuth:(const BOOL)bypassNativeAuth
                              completion:(void (^)(NSString *))completion
{
    NSString *const redirectURLScheme = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier].scheme;
    if (![[[[NSBundle mainBundle] infoDictionary] valueForKeyPath:@"CFBundleURLTypes.CFBundleURLSchemes.@unionOfArrays.self"] containsObject:redirectURLScheme]) { // https://forums.developer.apple.com/thread/31307
        NSAssert(NO, @"You must add the \"%@\" scheme to your info.plist's \"CFBundleURLTypes\"", redirectURLScheme);
        completion(nil);
        return;
    }
    
    NSString *const codeVerifier = [NSString stringWithFormat:@"%@-%@", [[NSUUID UUID] UUIDString], [[NSUUID UUID] UUIDString]];
    if (bypassNativeAuth) {
        [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                             codeVerifier:codeVerifier
                                               completion:completion];
    } else {
        NSURL *const tokenAuthURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier
                                                                                  codeVerifier:codeVerifier];
        [[UIApplication sharedApplication] openURL:tokenAuthURL
                                           options:@{}
                                 completionHandler:^(BOOL success) {
            if (success) {
                [self setTj_clientIdentifier:clientIdentifier];
                [self setTj_codeVerifier:codeVerifier];
                [self setTj_completion:completion];
            } else {
                [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                                     codeVerifier:codeVerifier
                                                       completion:completion];
            }
        }];
    }
}

+ (void)authenticateUsingSafariWithClientIdentifier:(NSString *const)clientIdentifier
                                       codeVerifier:(NSString *const)codeVerifier
                                         completion:(void (^)(NSString *))completion
{
    NSURL *const url = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier
                                                                 redirectURL:nil
                                                                codeVerifier:codeVerifier];
    NSString *const redirectURLScheme = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier].scheme;
    
    // Reference needs to be held as long as this is in progress, otherwise the UI disappears.
    static id session = nil;
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
            [(ASWebAuthenticationSession *)session setPresentationContextProvider:(id<ASWebAuthenticationPresentationContextProviding>)self];
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
                [self setTj_completion:completion];
            } else {
                completion(nil);
            }
        }];
    }
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
{
    return [self tryHandleAuthenticationCallbackWithURL:url
                                       clientIdentifier:[self tj_clientIdentifier]
                                           codeVerifier:[self tj_codeVerifier]
                                             completion:[self tj_completion]];
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
                              clientIdentifier:(NSString *const)clientIdentifier
                                  codeVerifier:(NSString *const)codeVerifier
                                    completion:(void (^)(NSString *))completion
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
        NSString *const token = [TJDropbox accessTokenFromDropboxAppAuthenticationURL:url] ?: [TJDropbox accessTokenFromURL:url withClientIdentifier:clientIdentifier];
        if (codeIsAccessToken) {
            code = token;
        }
        if (code) {
            if (codeVerifier) {
                [TJDropbox accessTokenFromCode:code
                          withClientIdentifier:clientIdentifier
                                  codeVerifier:codeVerifier
                                   redirectURL:redirectURL
                                    completion:^(NSString * _Nullable accessToken, NSError * _Nullable error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(accessToken);
                    });
                }];
            } else {
                completion(nil);
            }
        } else {
            completion(token);
        }
        
        [self setTj_clientIdentifier:nil];
        [self setTj_codeVerifier:nil];
        [self setTj_completion:nil];
        
        handledURL = YES;
    }
    return handledURL;
}

#pragma mark - ASWebAuthenticationPresentationContextProviding

+ (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session API_AVAILABLE(ios(13.0))
{
    return [[UIApplication sharedApplication] keyWindow];
}

@end
