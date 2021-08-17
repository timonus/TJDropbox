//
//  TJDropboxAuthenticator.h
//  Close-up
//
//  Created by Tim Johnsen on 3/14/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TJDropboxAuthenticationOptions : NSObject

/// Credentials will be long-lived.
- (instancetype)initWithGenerateRefreshToken;

/// Credentials will be short-lived after Sept. 30 2021 https://developers.dropbox.com/oauth-guide#using-refresh-tokens
- (instancetype)initWithBypassNativeAuth:(const BOOL)bypassNativeAuth
                              bypassPKCE:(const BOOL)bypassPKCE;

@end

API_AVAILABLE(ios(10.0)) @interface TJDropboxAuthenticator : NSObject

/**
 * Invoke this to initiate auth
 * @param clientIdentifier Your registered Dropbox client identifier.
 * @param bypassNativeAuth Pass @c YES to skip authentication via the Dropbox app and force auth to occur via the web.
 * @param completion Block invoked when auth is complete. @c accessToken will be @c nil if auth wasn't completed.
 */
+ (void)authenticateWithClientIdentifier:(NSString *const)clientIdentifier
                                 options:(nullable TJDropboxAuthenticationOptions *)options
                              completion:(void (^)(TJDropboxCredential *_Nullable))completion;

/// Invoke this from your app delegate's implementation of -application:openURL:options:, returns whether or not the URL was a completion callback to Dropbox auth.
+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url;

@end

NS_ASSUME_NONNULL_END
