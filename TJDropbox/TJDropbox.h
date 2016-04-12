//
//  TJDropbox.h
//  TJDropbox
//
//  Created by Tim Johnsen on 4/11/16.
//  Copyright © 2016 tijo. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TJDropbox : NSObject

// Authentication

/// Used to return the URL used to initate OAuth with Dropbox
+ (NSURL *)tokenAuthenticationURLWithClientIdentifier:(NSString *const)clientIdentifier redirectURL:(NSURL *)redirectURL;

/// Used to extract the access token returned from Dropbox OAuth
+ (nullable NSString *)accessTokenFromURL:(NSURL *)url withRedirectURL:(NSURL *)redirectURL;

@end

NS_ASSUME_NONNULL_END
