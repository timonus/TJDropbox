//
//  TJDropboxAuthenticator.h
//  Close-up
//
//  Created by Tim Johnsen on 3/14/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(10.0)) @interface TJDropboxAuthenticator : NSObject

/**
 * Invoke this to initiate auth
 * @param clientIdentifier Your registered Dropbox client identifier.
 * @param bypassNativeAuth Pass @c YES to skip authentication via the Dropbox app and force auth to occur via the web.
 * @param completion Block invoked when auth is complete. @c accessToken will be @c nil if auth wasn't completed.
 */
+ (void)authenticateWithClientIdentifier:(NSString *const)clientIdentifier
                     bypassingNativeAuth:(const BOOL)bypassNativeAuth
                           bypassingPKCE:(const BOOL)bypassingPKCE
                              completion:(void (^)(NSString *_Nullable accessToken))completion;

/// Invoke this from your app delegate's implementation of -application:openURL:options:, returns whether or not the URL was a completion callback to Dropbox auth.
+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url;

@end

NS_ASSUME_NONNULL_END
