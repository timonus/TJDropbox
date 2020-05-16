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

@interface TJDropboxAuthenticator ()

@property (nonatomic, copy, class) NSString *tj_clientIdentifier;
@property (nonatomic, copy, class) void (^tj_completion)(NSString *accessToken);

@end

@implementation TJDropboxAuthenticator

static NSString *_tj_clientIdentifier;
static void (^_tj_completion)(NSString *accessToken);

+ (void)setTj_clientIdentifier:(NSString *)tj_clientIdentifier
{
    _tj_clientIdentifier = tj_clientIdentifier;
}

+ (void)setTj_completion:(void (^)(NSString *))tj_completion
{
    _tj_completion = tj_completion;
}

+ (NSString *)tj_clientIdentifier
{
    return _tj_clientIdentifier;
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
    
    if (bypassNativeAuth) {
        [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                               completion:completion];
    } else {
        NSURL *const tokenAuthURL = [TJDropbox dropboxAppAuthenticationURLWithClientIdentifier:clientIdentifier];
        [[UIApplication sharedApplication] openURL:tokenAuthURL
                                           options:@{}
                                 completionHandler:^(BOOL success) {
            if (success) {
                [self setTj_clientIdentifier:clientIdentifier];
                [self setTj_completion:completion];
            } else {
                [self authenticateUsingSafariWithClientIdentifier:clientIdentifier
                                                       completion:completion];
            }
        }];
    }
}

+ (void)authenticateUsingSafariWithClientIdentifier:(NSString *const)clientIdentifier
                                         completion:(void (^)(NSString *))completion
{
    NSURL *const url = [TJDropbox tokenAuthenticationURLWithClientIdentifier:clientIdentifier];
    NSString *const redirectURLScheme = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier].scheme;
    
    // Reference needs to be held as long as this is in progress, otherwise the UI disappears.
    static id session = nil;
    void (^completionHandler)(NSURL *, NSError *) = ^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        // Process results.
        [self tryHandleAuthenticationCallbackWithURL:callbackURL
                                    clientIdentifier:clientIdentifier
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
                                             completion:[self tj_completion]];
}

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url
                              clientIdentifier:(NSString *const)clientIdentifier
                                    completion:(void (^)(NSString *))completion
{
    BOOL handledURL = NO;
    NSString *const redirectURLScheme = [TJDropbox defaultTokenAuthenticationRedirectURLWithClientIdentifier:clientIdentifier].scheme;
    if (url && redirectURLScheme && [url.absoluteString hasPrefix:redirectURLScheme]) {
        NSString *const token = [TJDropbox accessTokenFromDropboxAppAuthenticationURL:url] ?: [TJDropbox accessTokenFromURL:url withClientIdentifier:clientIdentifier];
        
        completion(token);
        
        [self setTj_clientIdentifier:nil];
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
