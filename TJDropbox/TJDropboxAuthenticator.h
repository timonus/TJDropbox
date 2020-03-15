//
//  TJDropboxAuthenticator.h
//  Close-up
//
//  Created by Tim Johnsen on 3/14/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(10.0)) @interface TJDropboxAuthenticator : NSObject

+ (void)authenticateWithClientIdentifier:(NSString *const)clientIdentifier
                     bypassingNativeAuth:(const BOOL)bypassNativeAuth
                              completion:(void (^)(NSString *))completion;

+ (BOOL)tryHandleAuthenticationCallbackWithURL:(NSURL *const)url;

@end

NS_ASSUME_NONNULL_END
